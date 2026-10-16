import Foundation

@MainActor final class ClaudeCodingAgent: CodingAgentServing {
    let provider = AIProvider.claude
    private(set) var connected = false
    var onEvent: ((CodingAgentEvent) -> Void)?
    private let rpc: AgentRPCProcess
    private var nodePath = ""
    private var sdkDirectory = ""
    private var apiKey = ""
    private var helperDirectory: URL?
    init(rpc: AgentRPCProcess = AgentRPCProcess()) {
        self.rpc = rpc
        rpc.onMessage = { [weak self] in self?.receive($0) }
        rpc.onDisconnect = { [weak self] in self?.connected = false; self?.onEvent?(.disconnected("Claude disconnected.")) }
    }
    func configure(node: String, sdkDirectory: String, apiKey: String) {
        self.nodePath = (node as NSString).expandingTildeInPath
        self.sdkDirectory = (sdkDirectory as NSString).expandingTildeInPath
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func nodeExecutable() -> String {
        let paths = ["/opt/homebrew/bin/node", "/usr/local/bin/node"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/node" }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }
    func connect() async throws {
        guard !connected else { return }
        guard FileManager.default.isExecutableFile(atPath: nodePath) else { throw CodingAgentError.unavailable("Choose Node.js 20+ to run the Claude Agent SDK.") }
        let manifest = URL(fileURLWithPath: sdkDirectory).appendingPathComponent("node_modules/@anthropic-ai/claude-agent-sdk/package.json")
        guard let data = try? Data(contentsOf: manifest), let package = try? JSONDecoder().decode(AgentJSON.self, from: data), package["name"].string == "@anthropic-ai/claude-agent-sdk" else {
            throw CodingAgentError.unavailable("Choose the folder containing node_modules/@anthropic-ai/claude-agent-sdk. Install the official SDK there first.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sieg-claude-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = folder.appendingPathComponent("bridge.mjs")
        try Self.bridge.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: script.path)
        helperDirectory = folder
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
        environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        if !apiKey.isEmpty { environment["ANTHROPIC_API_KEY"] = apiKey }
        environment["CLAUDE_AGENT_SDK_CLIENT_APP"] = "sieghart/0.1.0"
        do {
            try rpc.start(URL(fileURLWithPath: nodePath), arguments: [script.path, sdkDirectory], environment: environment)
            _ = try await rpc.request("initialize"); connected = true
        } catch { disconnect(); throw error }
    }
    func disconnect() {
        connected = false; apiKey = ""; rpc.stop(notify: false)
        if let helperDirectory { try? FileManager.default.removeItem(at: helperDirectory) }; helperDirectory = nil
    }
    func sessions() async throws -> [CodingSession] { try await rpc.request("list")["sessions"].array.compactMap(Self.session) }
    func messages(in session: CodingSession) async throws -> [CodingMessage] {
        try await rpc.request("read", params: .object(["id": .string(session.providerID), "directory": .string(session.directory)]))["messages"].array.compactMap(Self.message)
    }
    func create(in directory: String) async throws -> CodingSession {
        let result = try await rpc.request("create", params: .object(["directory": .string(directory)]))
        guard let session = Self.session(result["session"]) else { throw CodingAgentError.invalidResponse }; onEvent?(.session(session)); return session
    }
    func send(_ text: String, to session: CodingSession) async throws {
        guard text.utf8.count <= 16_384 else { throw CodingAgentError.unavailable("Keep each message under 16 KB.") }
        _ = try await rpc.request("send", params: .object(["id": .string(session.providerID), "directory": .string(session.directory), "text": .string(text)]))
    }
    func interrupt(_ session: CodingSession) async throws { _ = try await rpc.request("interrupt", params: .object(["id": .string(session.providerID)])) }
    func respond(to approval: CodingApproval, allow: Bool, answers: [String: String]) async throws {
        _ = try await rpc.request("approve", params: .object(["id": .string(approval.id), "allow": .bool(allow), "answers": .object(answers.mapValues(AgentJSON.string))]))
    }
    private func receive(_ packet: AgentJSON) {
        let params = packet["params"]
        switch packet["method"].string {
        case "session": if let session = Self.session(params) { onEvent?(.session(session)) }
        case "worker":
            guard let root = params["rootID"].string, let task = params["taskID"].string else { return }
            let sessionID = "claude:" + root
            onEvent?(.worker(CodingWorker(id: sessionID + ":worker:" + task, rootID: sessionID,
                parentID: params["parentTaskID"].string.map { sessionID + ":worker:" + $0 } ?? sessionID,
                provider: .claude, name: String((params["name"].string ?? "Claude agent").prefix(80)),
                task: String((params["task"].string ?? "No task reported").prefix(1000)),
                state: CodingAgentState(rawValue: params["state"].string ?? "unknown") ?? .unknown,
                detail: String((params["detail"].string ?? "").prefix(4000)), live: params["live"].bool ?? false,
                runID: params["runID"].string)))
        case "message": if let id = params["sessionID"].string, let message = Self.message(params["message"]) { onEvent?(.message(sessionID: "claude:" + id, message)) }
        case "delta": if let id = params["sessionID"].string, let message = params["messageID"].string, let text = params["text"].string { onEvent?(.delta(sessionID: "claude:" + id, messageID: message, text: text)) }
        case "approval":
            guard let id = params["id"].string, let session = params["sessionID"].string else { return }
            let questions = params["questions"].array.compactMap { value -> CodingQuestion? in
                guard let id = value["question"].string else { return nil }
                return CodingQuestion(id: id, title: value["header"].string ?? "Question", prompt: id, options: value["options"].array.compactMap { $0["label"].string })
            }
            onEvent?(.approval(CodingApproval(id: id, sessionID: "claude:" + session, title: params["title"].string ?? "Claude needs your decision", detail: params["detail"].string ?? "", questions: questions)))
        case "resolved": if let id = params["id"].string { onEvent?(.resolved(approvalID: id)) }
        default: break
        }
    }
    static func session(_ value: AgentJSON) -> CodingSession? {
        guard let id = value["id"].string else { return nil }
        return CodingSession(provider: .claude, providerID: id, title: String((value["title"].string ?? "Claude session").prefix(120)), directory: value["directory"].string ?? "", state: CodingAgentState(rawValue: value["state"].string ?? "unknown") ?? .unknown, updatedAt: value["updatedAt"].number.map { Date(timeIntervalSince1970: $0 / 1000) }, managed: value["managed"].bool ?? false, detail: value["detail"].string ?? "")
    }
    static func message(_ value: AgentJSON) -> CodingMessage? {
        guard let id = value["id"].string, let role = CodingMessage.Role(rawValue: value["role"].string ?? "") else { return nil }
        return CodingMessage(id: id, role: role, text: String((value["text"].string ?? "").prefix(32_768)))
    }
    // Independent glue around the official SDK. No SDK code or CLI credentials are copied.
    static let bridge = #"""
    import {createRequire} from 'node:module';
    import {pathToFileURL} from 'node:url';
    import path from 'node:path';
    import readline from 'node:readline';
    import {randomUUID} from 'node:crypto';
    const write=x=>process.stdout.write(JSON.stringify(x)+'\n');
    const event=(method,params)=>write({method,params});
    const reply=(id,result)=>write({id,result});
    const failure=(id,message)=>write({id,error:{message}});
    let sdk;
    try { const require=createRequire(path.join(process.argv[2],'package.json')); sdk=await import(pathToFileURL(require.resolve('@anthropic-ai/claude-agent-sdk')).href); }
    catch { failure('startup','Claude Agent SDK could not be loaded. Check the selected SDK folder.'); process.exit(1); }
    const records=new Map(), runs=new Map(), decisions=new Map(), workerTasks=new Map();
    const state=(id,value,detail='')=>{ const s=records.get(id); if(s){s.state=value;s.detail=detail;event('session',s);} };
    const resolveFor=id=>{for(const [key,d] of decisions){if(d.sessionID===id){d.resolve({behavior:'deny',message:'Turn ended.'});decisions.delete(key);event('resolved',{id:key});}}};
    const textOf=m=>typeof m?.content==='string'?m.content:(m?.content??[]).filter(x=>x.type==='text').map(x=>x.text).join('\n');
    const emitWorker=w=>event('worker',w);
    function taskEvent(rootID,m){
      if(m.type!=='system'||!m.task_id||!['task_started','task_progress','task_updated','task_notification'].includes(m.subtype))return;
      const key=rootID+':'+m.task_id, old=workerTasks.get(key);
      if(!old&&!['local_agent','remote_agent'].includes(m.task_type))return;
      if(m.subtype!=='task_started'&&old?.runID&&m.run_id&&old.runID!==m.run_id)return;
      const patch=m.patch??{}, status=m.status??patch.status;
      const states={completed:'completed',failed:'failed',stopped:'interrupted',killed:'interrupted',running:'working',pending:'ready'};
      const w={...old,rootID,taskID:m.task_id,parentTaskID:m.parent_task_id??old?.parentTaskID,
        name:old?.name??'Agent '+m.task_id.slice(-6),task:m.description??patch.description??old?.task??'No task reported',
        state:states[status]??(m.subtype==='task_started'||m.subtype==='task_progress'?'working':old?.state??'unknown'),
        detail:m.summary??m.last_tool_name??patch.error??old?.detail??'',live:true,runID:m.run_id??old?.runID,
        toolUseID:m.tool_use_id??old?.toolUseID};
      workerTasks.set(key,w);emitWorker(w);
    }
    async function run(id,text){
      const s=records.get(id), controller=new AbortController();
      runs.set(id,controller);s.managed=true;state(id,'working');
      const userID=randomUUID();
      event('message',{sessionID:id,message:{id:userID,role:'user',text}});
      let terminal=false, sawAssistant=false, messageID=randomUUID();
      const textParts=new Map();
      try{
        const options={cwd:s.directory,includePartialMessages:true,abortController:controller,permissionMode:'default',allowedTools:[],settingSources:[],maxTurns:25,forwardSubagentText:true,
          canUseTool:async(toolName,input,context)=>{
            if(controller.signal.aborted)return {behavior:'deny',message:'Interrupted.'};
            const request=randomUUID();state(id,'waiting');
            return await new Promise(resolve=>{
              decisions.set(request,{sessionID:id,input,resolve});
              event('approval',{id:request,sessionID:id,title:toolName==='AskUserQuestion'?'Claude has a question':`Allow ${toolName}?`,detail:String(input.command??input.file_path??JSON.stringify(input)).slice(0,4000),questions:toolName==='AskUserQuestion'?input.questions??[]:[]});
            });
          }};
        if(s.draft)options.extraArgs={'session-id':id};else options.resume=id;
        async function* input(){yield {type:'user',uuid:userID,session_id:id,message:{role:'user',content:text},parent_tool_use_id:null};}
        for await(const m of sdk.query({prompt:input(),options})){
          if(m.type==='system'&&m.subtype==='init'){
            if(m.session_id&&m.session_id!==id)throw Error('Unexpected session ID');
            s.draft=false;state(id,'working');
          }
          taskEvent(id,m);
          if(m.agent_id||m.parent_tool_use_id){
            const w=m.agent_id?workerTasks.get(id+':'+m.agent_id):Array.from(workerTasks.values()).find(x=>x.rootID===id&&x.toolUseID===m.parent_tool_use_id);
            if(w&&m.type==='assistant'){w.detail=textOf(m.message).slice(0,4000);emitWorker(w);}
            continue;
          }
          if(m.type==='stream_event'){
            const e=m.event;if(e?.type==='message_start')messageID=e.message.id??randomUUID();
            if(e?.delta?.type==='text_delta')event('delta',{sessionID:id,messageID,text:e.delta.text});
          }
          if(m.type==='assistant'){
            const body=textOf(m.message);if(body){
              const key=m.message?.id??messageID, parts=textParts.get(key)??new Map();
              parts.set(m.uuid??body,body);textParts.set(key,parts);sawAssistant=true;
              event('message',{sessionID:id,message:{id:key,role:'assistant',text:Array.from(parts.values()).join('\n\n').slice(0,32768)}});
            }
            for(const b of m.message?.content??[])if(b.type==='tool_use')event('message',{sessionID:id,message:{id:b.id,role:'tool',text:`${b.name} · requested`}});
          }
          if(m.type==='result'){
            terminal=true;if(!sawAssistant&&typeof m.result==='string')event('message',{sessionID:id,message:{id:randomUUID(),role:'assistant',text:m.result.slice(0,32768)}});
            state(id,m.is_error?'failed':'completed',m.is_error?'The provider reported a failed turn.':'');
          }
        }
        if(controller.signal.aborted&&!terminal)state(id,'interrupted');
        else if(!terminal)state(id,'failed','The stream ended without a completion result.');
      }catch{if(!terminal)state(id,controller.signal.aborted?'interrupted':'failed',controller.signal.aborted?'':'Claude failed. Check API credentials, SDK compatibility and connection.');}
      finally{resolveFor(id);runs.delete(id);for(const w of workerTasks.values())if(w.rootID===id){w.live=false;emitWorker(w);}}
    }
    async function handle(m){
      const p=m.params??{};
      try{
        switch(m.method){
          case 'initialize':if(typeof sdk.query!=='function'||typeof sdk.listSessions!=='function'||typeof sdk.getSessionMessages!=='function')throw Error('Unsupported SDK');reply(m.id,{});break;
          case 'list':{
            const list=await sdk.listSessions({limit:50});
            for(const x of list.slice(0,50)){const id=x.sessionId??x.session_id;if(!id||records.get(id)?.managed)continue;records.set(id,{id,title:x.customTitle??x.summary??'Claude session',directory:x.cwd??'',state:'unknown',managed:false,updatedAt:x.lastModified??0});}
            reply(m.id,{sessions:Array.from(records.values()).slice(0,50)});break;
          }
          case 'read':{
            const items=records.get(p.id)?.draft?[]:await sdk.getSessionMessages(p.id,{dir:p.directory||undefined,limit:100});
            const messages=[];
            for(const x of items.slice(-100)){
              const id=(x.type==='assistant'?x.message?.id:undefined)??x.uuid??randomUUID(), text=textOf(x.message).slice(0,32768);
              const previous=x.type==='assistant'?messages.find(m=>m.id===id):undefined;
              if(previous)previous.text=(previous.text+'\n\n'+text).slice(0,32768);
              else if(text)messages.push({id,role:x.type==='user'?'user':'assistant',text});
            }
            reply(m.id,{messages});break;
          }
          case 'create':{const id=randomUUID(),s={id,title:'New Claude conversation',directory:p.directory,state:'ready',managed:true,draft:true};records.set(id,s);reply(m.id,{session:s});break;}
          case 'send':
            if(!process.env.ANTHROPIC_API_KEY)throw Error('Add an Anthropic API key to send.');
            if(!records.has(p.id)||runs.has(p.id))throw Error('Select an idle session.');
            if(typeof p.text!=='string'||!p.text.trim()||Buffer.byteLength(p.text)>16384)throw Error('Message size invalid.');
            if(!records.get(p.id).directory)throw Error('The session has no project directory. Create a conversation in a selected folder.');
            reply(m.id,{});void run(p.id,p.text);break;
          case 'interrupt':if(!runs.has(p.id))throw Error('This turn is not attached here.');runs.get(p.id).abort();resolveFor(p.id);reply(m.id,{});break;
          case 'approve':{const d=decisions.get(p.id);if(!d)throw Error('Request expired.');decisions.delete(p.id);d.resolve(p.allow?{behavior:'allow',updatedInput:{...d.input,...(d.input.questions?{answers:p.answers??{}}:{})}}:{behavior:'deny',message:'Declined by the user.'});event('resolved',{id:p.id});state(d.sessionID,'working');reply(m.id,{});break;}
          default:throw Error('Unsupported request.');
        }
      }catch(e){failure(m.id,['send','interrupt','approve'].includes(m.method)?e.message:'SDK request failed. Check the selected SDK version.');}
    }
    readline.createInterface({input:process.stdin}).on('line',line=>{if(Buffer.byteLength(line)>262144)return;try{void handle(JSON.parse(line));}catch{}}).on('close',()=>{for(const c of runs.values())c.abort();for(const id of runs.keys())resolveFor(id);process.exit(0);});
    """#
}
