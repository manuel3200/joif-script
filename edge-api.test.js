const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),net=require('node:net'),{spawn}=require('node:child_process');
test('real SQLite backend creates, checks and revokes a test account without accessing production data',async t=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'mivpn-edge-api-'));
  for(const [from,to] of [['server.js','server.js'],['db.js','db.js'],['backend-security.js','backend-security.js'],['account-reconciler.js','account-reconciler.js'],['joif.js','joif.js']])fs.copyFileSync(path.join(__dirname,from),path.join(dir,to));
  fs.mkdirSync(path.join(dir,'public'));
  const port=await new Promise(resolve=>{const s=net.createServer().listen(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>resolve(p));});});
  const child=spawn(process.execPath,[path.join(dir,'server.js')],{env:{...process.env,NODE_PATH:[path.join(__dirname,'node_modules'),process.env.NODE_PATH].filter(Boolean).join(path.delimiter),PORT:String(port),SESSION_SECRET:'temporary-test-secret-'.repeat(3)},stdio:['ignore','pipe','pipe']});
  const stopped=new Promise(resolve=>child.once('exit',resolve));
  t.after(async()=>{child.kill();await stopped;fs.rmSync(dir,{recursive:true,force:true});});
  let logs='';
  await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(Error('El backend aislado no arrancó.')),10000);
    child.stdout.on('data',chunk=>{logs+=chunk;if(logs.includes('ejecutándose')){clearTimeout(timer);resolve();}});
    child.stderr.on('data',()=>{});child.once('exit',()=>{clearTimeout(timer);reject(Error('El backend aislado terminó antes de arrancar.'));});
  });
  const password=logs.match(/Contraseña Temporal: ([A-Za-z0-9_-]+)/)?.[1];assert.ok(password);
  const base='http://127.0.0.1:'+port;
  const post=(route,body,token)=>fetch(base+route,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
  assert.equal((await post('/api/auth/login',{username:'admin',password:'incorrect'})).status,401);
  const login=await post('/api/auth/login',{username:'admin',password});assert.equal(login.status,200);const {token}=await login.json();
  assert.equal((await post('/api/users',{username:'stage2test',password:'temporary-account-123',expiration_date:'2099-01-01',max_connections:1},token)).status,201);
  assert.equal((await fetch(base+'/check/stage2test')).status,200);
  assert.ok((await (await fetch(base+'/check')).json()).includes('stage2test'));
  const generated=await post('/api/users/stage2test/config',{host:'example.invalid'},token);assert.equal(generated.status,200);assert.ok((await generated.json()).data.startsWith('JOIF_VPN_V1:'));
  assert.equal((await post('/api/users/stage2test/revoke',{},token)).status,200);
  assert.equal((await fetch(base+'/check/stage2test')).status,403);
  assert.ok(!(await (await fetch(base+'/check')).json()).includes('stage2test'));
  assert.equal((await post('/api/auth/change-password',{newPassword:'short'},token)).status,400);
});

