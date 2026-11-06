const {test}=require('node:test'), assert=require('node:assert/strict'), fs=require('node:fs'), vm=require('node:vm');
const security=require('./backend-security');
function fixture(platform='win32') {
  const routes=new Map(), commands=[],writes=[],state={user:{id:1,username:'testuser',password:'strong-pass-123',hwid:null,status:'active',expiration_date:'2099-01-01'}};
  const app={use(){},listen(){},post(route,...handlers){routes.set('POST '+route,handlers.at(-1));},get(route,...handlers){for(const r of [route].flat())routes.set('GET '+r,handlers.at(-1));},delete(route,...handlers){routes.set('DELETE '+route,handlers.at(-1));}};
  const db={async query(sql,params){if(sql.startsWith('SELECT id FROM users'))return {rows:[],rowCount:0};if(sql.startsWith('SELECT'))return {rows:state.user?[state.user]:[],rowCount:state.user?1:0};writes.push({sql,params});return {lastID:2,rowCount:1};}};
  const dependencies={'express':()=>app,'cors':()=>()=>{},'child_process':{exec(){},spawn(){return {on(){}};}},'./db':db,'path':require('node:path'),'jsonwebtoken':{},'dotenv':{config(){}},'./joif':require('./joif'),'./account-reconciler':{startReconciler(){}},'./backend-security':{...security,sessionSecret:()=> 'test-only-secret-'.repeat(4),async run(file,args,input){commands.push({file,args,input});if(state.failSystem)throw Error('system failure');return 'testuser:x:1001:1001::/:/bin/false';}}};
  dependencies.express.json=()=>()=>{};dependencies.express.static=()=>()=>{};
  vm.runInNewContext(fs.readFileSync(__dirname+'/server.js','utf8'),{require:name=>dependencies[name],__dirname,process:{platform,env:{}},console:{log(){},error(){}},setTimeout(){}});
  const call=async(name,request={})=>{const response={statusCode:200,status(n){this.statusCode=n;return this;},set(){return this;},json(body){this.body=body;return this;}};await routes.get(name)({body:{},params:{username:'testuser'},...request},response);return response;};
  return {call,commands,writes,state};
}
test('account API rejects expired/revoked accounts and produces real JOIF for active users',async()=>{
  const f=fixture();
  assert.equal((await f.call('GET /check/:id',{params:{id:'testuser'}})).statusCode,200);
  const generated=await f.call('POST /api/users/:username/config',{body:{host:'example.invalid'}}); assert.ok(generated.body.data.startsWith('JOIF_VPN_V1:'));
  f.state.user.status='revoked';assert.equal((await f.call('GET /check/:id',{params:{id:'testuser'}})).statusCode,403);
  assert.equal((await f.call('POST /api/users/:username/config',{body:{host:'example.invalid'}})).statusCode,403);
  f.state.user.status='active';f.state.user.expiration_date='2020-01-01';assert.equal((await f.call('GET /check/:id',{params:{id:'testuser'}})).statusCode,403);
});
test('failed Linux account creation does not write DB; valid creation uses argument arrays and stdin',async()=>{
  const f=fixture('linux');const request={body:{username:'newuser',password:'strong-pass-123',expiration_date:'2099-12-01',max_connections:1}};
  f.state.failSystem=true;assert.equal((await f.call('POST /api/users',request)).statusCode,500);assert.equal(f.writes.length,0);
  f.state.failSystem=false;assert.equal((await f.call('POST /api/users',request)).statusCode,201);
  const passwd=f.commands.find(c=>c.args.includes('chpasswd'));assert.equal(passwd.input,'newuser:strong-pass-123\n');
  assert.ok(!f.commands.some(c=>c.args.some(v=>v.includes('strong-pass'))));
  assert.equal((await f.call('POST /api/users',{body:{...request.body,username:'bad;cmd'}})).statusCode,400);
});
test('Linux delete and revoke preserve DB on system failure',async()=>{
  const f=fixture('linux');f.state.failSystem=true;
  assert.equal((await f.call('DELETE /api/users/:username')).statusCode,500);assert.equal(f.writes.length,0);
  assert.equal((await f.call('POST /api/users/:username/revoke')).statusCode,500);assert.equal(f.writes.length,0);
  f.state.failSystem=false;assert.equal((await f.call('POST /api/users/:username/revoke')).statusCode,200);
  assert.ok(f.writes.some(w=>w.sql.includes("status = 'revoked'")));
});

