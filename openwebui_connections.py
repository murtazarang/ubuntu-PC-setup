"""Open WebUI 0.13.4 native configuration. Never replace unrelated connections."""
import copy, json, pathlib

def contains(actual, expected):
 if isinstance(expected,dict):return isinstance(actual,dict) and all(k in actual and contains(actual[k],v) for k,v in expected.items())
 if isinstance(expected,list):return isinstance(actual,list) and len(actual)==len(expected) and all(contains(a,b) for a,b in zip(actual,expected))
 return actual==expected

def update(api,get_path,post_path,old,new):
 if old==new:return
 if api.request(get_path)!=old:raise ValueError('Configuration changed concurrently; rerun without other admin edits')
 api.request(post_path,json.dumps(new).encode())
 if not contains(api.request(get_path),new):raise ValueError('Configuration readback differs; inspect Open WebUI settings before continuing')

def configure(api,key_file,image_model):
 key=pathlib.Path(key_file).read_text().strip()
 if len(key)<24:raise ValueError('Missing/invalid locally generated Wikipedia API key')
 # Verify mcpo is reachable before storing its connection. Never print its secret.
 tool={'url':'http://127.0.0.1:8002','path':'/openapi.json','type':'openapi','auth_type':'bearer','key':key,'config':{'enable':True},'info':{'id':'pc-setup-wikipedia','name':'Offline Wikipedia'}}
 schema=api.request('/api/v1/configs/tool_servers/verify',json.dumps(tool).encode())
 if not isinstance(schema,dict) or not schema.get('paths'):raise ValueError('Wikipedia bridge did not return a usable OpenAPI schema; start it first')
 old=api.request('/api/v1/configs/tool_servers');new=copy.deepcopy(old)
 entries=new.get('TOOL_SERVER_CONNECTIONS') or [];new['TOOL_SERVER_CONNECTIONS']=entries
 existing=[x for x in entries if (x.get('info') or {}).get('id')=='pc-setup-wikipedia' or x.get('url','').rstrip('/')==tool['url']]
 if existing:
  if len(existing)!=1 or not contains(existing[0],tool):raise ValueError('Existing Wikipedia connection differs; preserved')
 else:entries.append(tool)
 update(api,'/api/v1/configs/tool_servers','/api/v1/configs/tool_servers',old,new)
 old=api.request('/openai/config');new=copy.deepcopy(old)
 urls=new['OPENAI_API_BASE_URLS'];keys=new['OPENAI_API_KEYS'];configs=new['OPENAI_API_CONFIGS']
 endpoint='http://127.0.0.1:8000/v1'
 if urls==['https://api.openai.com/v1'] and keys in ([],['']) and configs=={}:
  urls.clear();keys.clear()
 if endpoint not in urls:
  while len(keys)<len(urls):keys.append('')
  index=str(len(urls));urls.append(endpoint);keys.append('');configs[index]={'enable':True}
 else:
  index=str(urls.index(endpoint))
  if not configs.get(index,{}).get('enable',True):raise ValueError('Existing Colibri text connection is disabled; preserved for user review')
 new['ENABLE_OPENAI_API']=True
 update(api,'/openai/config','/openai/config/update',old,new)
 old=api.request('/api/v1/images/config');new=copy.deepcopy(old)
 image={'id':'pc-setup-colibri-image','name':'Colibri Qwen Image','type':'openai','url':'http://127.0.0.1:8001/v1','key':'','config':{'enable':True,'capabilities':{'image_generation':True,'image_edit':False},'model_ids':[image_model],'auth_type':'none','size':'auto','params':{'n':1,'response_format':'b64_json'}}}
 entries=new.get('IMAGE_CONNECTIONS') or [];new['IMAGE_CONNECTIONS']=entries
 existing=[x for x in entries if x.get('id')==image['id'] or x.get('url','').rstrip('/')==image['url']]
 if existing:
  if len(existing)!=1 or not contains(existing[0],image):raise ValueError('Existing image connection differs; preserved')
 else:
  if not entries:
   new.update(ENABLE_IMAGE_GENERATION=True,ENABLE_IMAGE_PROMPT_GENERATION=False,ENABLE_IMAGE_EDIT=False,IMAGE_GENERATION_DEFAULT_MODEL=image['id']+':'+image_model,IMAGE_EDIT_DEFAULT_MODEL='')
  entries.append(image)
 update(api,'/api/v1/images/config','/api/v1/images/config/update',old,new)
 print('Verified native Colibri text/image and offline Wikipedia connection configuration. Model inference and corpus searches are separate runtime checks.')
