import Foundation

enum IntegrationProtocolFixtures {
    static let codex = #"""
    #!/usr/bin/python3
    import sys,json,time
    session={'id':'owned','preview':'Owned fixture','cwd':'/private/tmp','status':{'type':'idle'}}
    def out(x):
      raw=json.dumps(x)+'\n'
      # Split the UTF-8 frame to exercise incremental framing.
      sys.stdout.write(raw[:7]);sys.stdout.flush();sys.stdout.write(raw[7:]);sys.stdout.flush()
    def event(method,params):out({'method':method,'params':params})
    for line in sys.stdin:
      m=json.loads(line);method=m.get('method');p=m.get('params',{});result={}
      if method=='initialize':
        assert p['capabilities']['experimentalApi'] is True;result={}
      elif method=='account/read':result={'account':{'type':'fixture'}}
      elif method=='thread/list':result={'data':[dict(session,status={'type':'notLoaded'})]}
      elif method=='thread/read':
        assert p.get('includeTurns') is False;result={'thread':dict(session,turns=[])}
      elif method=='thread/turns/list':
        assert p.get('sortDirection')=='desc' and p.get('itemsView')=='notLoaded'
        result={'data':[{'id':'history-turn','items':[]}],'nextCursor':None}
      elif method=='thread/items/list':
        assert p.get('sortDirection')=='desc'
        result={'data':[{'turnId':'history-turn','item':{'id':'saved','type':'userMessage','content':[{'type':'text','text':'Saved question'}]}}]}
      elif method=='thread/resume':
        assert p.get('excludeTurns') is True;result={'thread':session}
      elif method=='thread/start':result={'thread':session}
      elif method=='turn/start':
        text=p['input'][0]['text'];turn={'id':text,'status':'inProgress'}
        event('turn/started',{'threadId':'owned','turn':turn})
        if text=='fast':
          event('item/agentMessage/delta',{'threadId':'owned','itemId':'reply','delta':'Hello '})
          event('item/agentMessage/delta',{'threadId':'owned','itemId':'reply','delta':'Ada'})
          event('turn/completed',{'threadId':'owned','turn':{'id':text,'status':'completed'}})
          event('thread/status/changed',{'threadId':'owned','status':{'type':'idle'}})
        elif text=='fleet':
          ids=['child-'+str(i) for i in range(5)]
          item={'id':'spawn','type':'collabAgentToolCall','tool':'spawnAgent','status':'completed','senderThreadId':'owned','receiverThreadIds':ids,'prompt':'Review the parser','agentsStates':{x:{'status':'running'} for x in ids}}
          event('item/completed',{'threadId':'owned','item':item})
          item={**item,'id':'wait','tool':'wait','agentsStates':{'child-0':{'status':'running'},'child-1':{'status':'interrupted'},'child-2':{'status':'errored'},'child-3':{'status':'pendingInit'},'child-4':{'status':'completed','message':'Review done'}}}
          event('item/completed',{'threadId':'owned','item':item})
          event('turn/completed',{'threadId':'owned','turn':{'id':text,'status':'completed'}})
        elif text=='approval':out({'id':42,'method':'item/commandExecution/requestApproval','params':{'threadId':'owned','command':'fixture command'}})
        elif text=='unsupported':out({'id':43,'method':'item/tool/call','params':{'threadId':'owned'}})
        result={'turn':turn}
      elif method=='turn/interrupt':
        event('turn/completed',{'threadId':'owned','turn':{'id':'hold','status':'interrupted'}})
        event('thread/status/changed',{'threadId':'owned','status':{'type':'idle'}})
      elif m.get('id')==42 and not method:
        assert m['result']['decision']=='decline'
        event('serverRequest/resolved',{'threadId':'owned','requestId':42})
        event('turn/completed',{'threadId':'owned','turn':{'id':'approval','status':'completed'}})
        continue
      elif m.get('id')==43 and not method:
        assert m['error']['code']==-32601
        event('turn/completed',{'threadId':'owned','turn':{'id':'unsupported','status':'failed'}})
        # Error notification must not erase terminal state in the adapter.
        event('error',{'threadId':'owned'})
        continue
      elif method=='timeout':continue
      elif method=='disconnect':sys.exit(0)
      if 'id' in m:out({'id':m['id'],'result':result})
    """#
    static let claude = #"""
    export async function listSessions(){return [{sessionId:'saved',summary:'Stored fixture',cwd:'/private/tmp'}];}
    const histories=new Map();
    export async function getSessionMessages(id){if(id==='saved')return [{uuid:'saved-msg',type:'user',message:{content:'Fixture history'}}];return histories.get(id)??[];}
    export async function* query({prompt:input,options}){
      const envelope=(await input[Symbol.asyncIterator]().next()).value;
      const prompt=envelope.message.content, reply='reply-'+envelope.uuid;
      if(!envelope.uuid)throw Error('Missing stable UUID');
      if(options.permissionMode!=='default'||options.settingSources.length!==0)throw Error('Fixture permissions');
      const id=options.resume??options.extraArgs['session-id'];
      histories.set(id,[...(histories.get(id)??[]),{uuid:envelope.uuid,type:'user',message:envelope.message}]);
      yield {type:'system',subtype:'init',session_id:id};
      if(prompt==='hold'){
        await new Promise((resolve,reject)=>{if(options.abortController.signal.aborted)return reject(Error('aborted'));options.abortController.signal.addEventListener('abort',()=>reject(Error('aborted')),{once:true});});return;
      }
      if(prompt==='permission')await options.canUseTool('Bash',{command:'fixture command'},{});
      if(prompt==='question'){
        const decision=await options.canUseTool('AskUserQuestion',{questions:[{question:'Choose a folder?',header:'Folder',options:[{label:'src'}]}]},{});
        if(decision.updatedInput.answers['Choose a folder?']!=='src')throw Error('Wrong question answer');
      }
      if(prompt==='no-result')return;
      if(prompt==='fleet'){
        yield {type:'system',subtype:'task_started',task_id:'shell',task_type:'local_bash',description:'Not an agent'};
        for(let i=0;i<5;i++){
          yield {type:'system',subtype:'task_started',task_id:'child-'+i,run_id:'new-'+i,task_type:'local_agent',description:'Review part '+i,parent_task_id:i===4?'child-0':undefined};
          yield {type:'system',subtype:'task_progress',task_id:'child-'+i,run_id:'new-'+i,description:'Review part '+i,last_tool_name:'Read'};
        }
        yield {type:'system',subtype:'task_notification',task_id:'child-0',run_id:'old-0',status:'completed',summary:'Stale completion'};
        yield {type:'assistant',agent_id:'child-4',parent_tool_use_id:'tool-child',message:{id:'child-msg',content:[{type:'text',text:'Child-only output'}]}};
        yield {type:'system',subtype:'task_notification',task_id:'child-4',run_id:'new-4',status:'completed',summary:'Review done'};
      }
      yield {type:'stream_event',event:{type:'message_start',message:{id:reply}}};
      yield {type:'stream_event',event:{delta:{type:'text_delta',text:'Hello Ada'}}};
      const assistant={uuid:'stored-'+envelope.uuid,type:'assistant',message:{id:reply,content:[{type:'text',text:'Hello Ada'}]}};
      histories.set(id,[...histories.get(id),assistant]);yield assistant;
      if(prompt==='two-parts'){
        const part={uuid:'part-'+envelope.uuid,type:'assistant',message:{id:reply,content:[{type:'text',text:'Next step'}]}};
        histories.set(id,[...histories.get(id),part]);yield part;
      }
      yield {type:'result',subtype:'success',is_error:false,result:'Hello Ada'};
    }
    """#
}

enum IntegrationNewChatFixture {
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

enum IntegrationDesktopFixture {
    static let fixture = #"""
    #!/usr/bin/python3
    import sys,json
    root='11111111-1111-4111-8111-111111111111'
    for line in sys.stdin:
      m=json.loads(line); method=m.get('method'); p=m.get('params',{}); result={}
      if method=='initialize': result={}
      elif method=='account/read': result={'account':{'type':'fixture'}}
      elif method=='thread/list':
        assert p['sortKey']=='updated_at' and 'subAgent' in p['sourceKinds']
        result={'data':[{'id':root,'name':'Actual selected chat','originator':'codex_work_desktop','status':{'type':'notLoaded'}},{'id':'writer-conflict','status':{'type':'notLoaded'}}]}
      elif method=='thread/resume':
        assert p['threadId']=='writer-conflict', 'Desktop root must queue without resuming'
        sys.stdout.write(json.dumps({'id':m['id'],'error':{'code':-32600,'message':'thread writer-conflict already has an active writer'}})+'\n');sys.stdout.flush();continue
      elif method=='thread/queue/add':
        assert p['threadId'] in [root,'writer-conflict'] and p['input'][0]['text']
        assert p['clientUserMessageId']
        result={'queuedSubmission':{'id':'queue-fixture','clientUserMessageId':p['clientUserMessageId'],'input':p['input']}}
      elif method=='turn/start': raise AssertionError('Never start a new writer for the desktop root')
      if 'id' in m: sys.stdout.write(json.dumps({'id':m['id'],'result':result})+'\n');sys.stdout.flush()
    """#
}
