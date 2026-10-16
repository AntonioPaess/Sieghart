import Foundation

// Owned stdio runtime reproduces Codex's unmaterialized thread behavior.
// No installed account, provider request, or user's conversation is accessed.
enum NewCodexChatChecks {
    @MainActor static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sieg-new-chat-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("runtime.py")
        try fixture.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let service = CodexCodingAgent(executable: { script }, desktopDirectory: folder)
        let room = AgentRoomViewModel(services: [.codex: service])
        defer { room.shutdown() }
        await room.connect(.codex)
        precondition(room.sessions.isEmpty && room.selectedID == nil)
        await room.create(.codex, directory: folder.path)
        guard let fresh = room.selected else { preconditionFailure("New chat did not open") }
        precondition(fresh.providerID == "fresh" && fresh.state == .ready && fresh.managed)
        precondition(room.page == .chat && room.notice == nil && room.messages.isEmpty && room.loadingID == nil)
        await room.refresh(.codex)
        precondition(room.selectedID == fresh.id && room.sessions.contains { $0.id == fresh.id })
        await room.select(fresh.id)
        let log = folder.appendingPathComponent("requests.txt")
        let beforeSend = try String(contentsOf: log, encoding: .utf8)
        precondition(!beforeSend.contains("thread/read") && !beforeSend.contains("thread/turns/list"))

        room.draft = "retryable failure"
        await room.send()
        precondition(room.draft == "retryable failure" && room.selected?.state == .ready)
        precondition(room.notice == "Fixture first send rejected" && room.messages.isEmpty)
        await room.select(fresh.id)
        let afterFailure = try String(contentsOf: log, encoding: .utf8)
        precondition(!afterFailure.contains("thread/read"))

        room.draft = "first question"
        await room.send()
        for _ in 0..<300 {
            if room.selected?.state == .completed && room.messages.contains(where: { $0.text == "First reply" }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(room.selected?.state == .completed && room.selected?.turnID == nil)
        precondition(room.messages.filter { $0.text == "first question" }.count == 1)
        precondition(room.messages.contains { $0.text == "First reply" } && room.draft.isEmpty && room.notice == nil)
        // First history request after admission can still race persistence.
        let pendingHistory = try await service.messages(in: fresh)
        precondition(pendingHistory.isEmpty)
        await room.select(fresh.id)
        precondition(room.notice == nil && room.messages.count == 2)
        precondition(room.messages.map(\.text) == ["first question", "First reply"])
        let persisted = try await service.sessions()
        precondition(persisted.first?.state == .completed && persisted.first?.managed == true)
        do {
            let missing = CodingSession(provider: .codex, providerID: "missing", title: "Missing", directory: folder.path)
            _ = try await service.messages(in: missing)
            preconditionFailure("An ordinary history error must remain visible")
        } catch CodingAgentError.unavailable(let reason) {
            precondition(reason == "No such thread")
        }
        print("New Codex chat: empty creation, refresh, retry, first turn and history persistence passed using an owned fixture.")
    }

    static let fixture = #"""
    #!/usr/bin/python3
    import sys,json,pathlib
    folder=pathlib.Path(__file__).parent
    started=False
    persisted=False
    first_history=True
    fresh={'id':'fresh','preview':'','cwd':str(folder),'path':str(folder/'not-materialized.jsonl'),'status':{'type':'idle'}}
    def out(x):
      print(json.dumps(x),flush=True)
    def event(method,params):
      out({'method':method,'params':params})
    for line in sys.stdin:
      m=json.loads(line); method=m.get('method'); p=m.get('params',{}); result={}
      if method:
        with (folder/'requests.txt').open('a') as log:log.write(method+'\n')
      if method=='initialize':result={}
      elif method=='account/read':result={'account':{'type':'fixture'}}
      elif method=='thread/list':result={'data':[fresh] if persisted else []}
      elif method=='thread/start':
        assert p['cwd']==str(folder)
        assert p['sandbox']=='workspace-write' and p['approvalPolicy']=='untrusted'
        started=True
        event('thread/started',{'thread':fresh})
        result={'thread':fresh}
      elif method=='thread/read':
        if p['threadId']!='fresh':
          out({'id':m['id'],'error':{'code':-32602,'message':'No such thread'}});continue
        assert persisted, 'empty thread must not read history'
        result={'thread':fresh}
      elif method=='thread/turns/list':
        assert persisted, 'history pager rejects fresh threads'
        if first_history:
          first_history=False
          out({'id':m['id'],'error':{'code':-32602,'message':'thread/turns/list is unavailable before first user message'}});continue
        result={'data':[{'id':'first-turn'}]}
      elif method=='thread/items/list':
        assert persisted
        result={'data':[{'turnId':'first-turn','item':{'id':'assistant-first','type':'agentMessage','text':'First reply'}},{'turnId':'first-turn','item':{'id':'user-first','type':'userMessage','content':[{'type':'text','text':'first question'}]}}]}
      elif method=='turn/start':
        assert started and p['threadId']=='fresh'
        assert p['approvalPolicy']=='untrusted'
        text=p['input'][0]['text']
        if text=='retryable failure':
          out({'id':m['id'],'error':{'code':-32602,'message':'Fixture first send rejected'}});continue
        assert text=='first question'
        persisted=True
        event('turn/started',{'threadId':'fresh','turn':{'id':'first-turn','status':'inProgress'}})
        event('item/completed',{'threadId':'fresh','item':{'id':'user-first','type':'userMessage','content':[{'type':'text','text':text}]}})
        event('item/completed',{'threadId':'fresh','item':{'id':'assistant-first','type':'agentMessage','text':'First reply'}})
        event('turn/completed',{'threadId':'fresh','turn':{'id':'first-turn','status':'completed'}})
        result={'turn':{'id':'first-turn','status':'inProgress'}}
      elif method=='thread/resume':
        raise AssertionError('Ada already owns this fresh thread')
      if 'id' in m:out({'id':m['id'],'result':result})
    """#
}
