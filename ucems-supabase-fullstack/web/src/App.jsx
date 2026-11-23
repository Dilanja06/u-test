import React,{useEffect,useRef,useState} from 'react';
import {supabase,configured,assertReady,call} from './client.js';
import {store,loadSession,refresh,checkout,vOf,clubOf,ownClubIds} from './data.js';
import './admin.css';
import './loading.css';
import './demo-login.css';

const nav={
 student:[['dashboard','Dashboard','grid'],['explore','Explore events','compass'],['calendar','Calendar','calendar'],['events','My events','ticket'],['clubs','Clubs','users'],['memberships','My memberships','users'],['payments','Payments','card'],['badges','My badges','award'],['notifications','Notifications','bell'],['profile','Profile','user']],
 committee:[['dashboard','Overview','grid'],['proposals','Event proposals','clipboard'],['members','Membership requests','users'],['registrations','Event registrations','ticket'],['finance','Finance','card'],['clubs','Clubs','users'],['attendance','Check-in','scan'],['badges','Badge authorization','award'],['permissions','My role & permissions','shield'],['notifications','Notifications','bell'],['profile','Profile','user']],
 lecturer:[['dashboard','Overview','grid'],['reviews','Review queue','check'],['notifications','Notifications','bell'],['profile','Profile','user']],
 authority:[['dashboard','Overview','grid'],['reviews','Approval queue','check'],['notifications','Notifications','bell'],['profile','Profile','user']],
 admin:[['dashboard','Overview','grid'],['admin','Administration','settings'],['proposals','All proposals','clipboard'],['audit','Audit history','shield'],['clubs','Club directory','users'],['notifications','Notifications','bell'],['profile','Profile','user']],
};

const committeePositions=['President','Vice President','Secretary','Vice Secretary','Treasurer'];
const committeePermissions=[
 ['club.members.view','View club memberships'],
 ['club.members.manage','Manage membership requests'],
 ['club.members.policy','Configure membership policy'],
 ['event.create','Create event drafts'],
 ['event.edit','Edit event details'],
 ['event.proposal.submit','Submit proposal versions'],
 ['event.publish','Publish approved events'],
 ['event.cancel','Cancel published events'],
 ['proposal.comment','Comment on proposals'],
 ['registration.view','View event registrations'],
 ['registration.manage','Manage event registrations'],
 ['registration.verify_external','Verify external registrations'],
 ['registration.export','Export event participants'],
 ['attendance.scan','Scan attendance QR codes'],
 ['attendance.view','View attendance records'],
 ['badge.define','Define club badges'],
 ['badge.nominate','Nominate badge candidates'],
 ['badge.authorize','Authorize badge candidates'],
 ['finance.view','View club finances'],
 ['finance.refund.approve','Approve club refunds'],
 ['finance.reconcile','Reconcile settlements'],
 ['finance.export','Export finance records'],
];
const hasPermission=(clubId,permission)=>store.committeePermissions.some(grant=>
 grant.club_id===clubId&&grant.permission_key===permission&&grant.enabled
);
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const date=x=>x?new Date(x).toLocaleDateString('en',{day:'numeric',month:'short',year:'numeric'}):'—';
const time=x=>x?new Date(x).toLocaleTimeString('en',{hour:'2-digit',minute:'2-digit'}):'—';
const money=x=>x>0?`USD ${(x/100).toFixed(2)} (test)`:'Free';
const clubLogoUrl=club=>club?.logo_path?supabase.storage.from('club-logos').getPublicUrl(club.logo_path).data.publicUrl:null;
const Status=({s})=><span className={`tag tag-${esc(s||'pending')}`}>{String(s||'pending').replaceAll('_',' ')}</span>;
const Empty=({title,subtitle=''})=><div className="empty"><h3>{title}</h3>{subtitle&&<p>{subtitle}</p>}</div>;

function Auth({onDemo}){
 const [busy,setBusy]=useState(false),[busyAction,setBusyAction]=useState(''),[toast,setToast]=useState('');
 const [email,setEmail]=useState('');
 const demoAccounts=[
  {label:'Admin',role:'admin'},
  {label:'Student',role:'student'},
  {label:'Committee',role:'committee'},
  {label:'Coordinator',role:'lecturer'},
  {label:'Authority',role:'authority'},
 ];
 async function signIn(email,password,action='signin'){setBusy(true);setBusyAction(action);setToast('');
  try{assertReady();const {error}=await supabase.auth.signInWithPassword({email,password});if(error)throw error;}
  catch(error){setToast(error.message)}finally{setBusy(false)}
 }
 async function login(e){e.preventDefault();const f=new FormData(e.currentTarget);
  await signIn(String(f.get('email')),String(f.get('password')));
 }
 async function requestPasswordReset(){
  if(!email.trim()){setToast('Enter your email address first.');return}
  setBusy(true);setBusyAction('recovery');setToast('');
  try{assertReady();const {error}=await supabase.auth.resetPasswordForEmail(email.trim(),{redirectTo:window.location.origin});if(error)throw error;setToast('If this account can sign in, a password reset link has been sent to its email address.')}
  catch(error){setToast(error.message||'Could not request a password reset.')}
  finally{setBusy(false)}
 }
 async function signup(e){e.preventDefault();const f=new FormData(e.currentTarget);setBusy(true);setBusyAction('signup');setToast('');
  try{assertReady();const {data,error}=await supabase.auth.signUp({email:String(f.get('email')),password:String(f.get('password')),options:{data:{full_name:String(f.get('full_name'))}}});if(error)throw error;if(!data.session)setToast('Check your email to confirm your account. Then sign in.');}
  catch(error){setToast(error.message)}finally{setBusy(false)}
 }
 return <div className="auth-wrap"><aside className="auth-panel"><div className="brand auth-brand"><span className="brand-mark">✦</span> UniEvents</div><div><span className="eyebrow">UNIVERSITY CLUB &amp; EVENT MANAGEMENT</span><h1>One campus.<br/><em>Every experience.</em></h1><p>From club proposals to unforgettable moments. Welcome to your university's connected platform.</p></div><small>UCEMS · Academic V1 · Supabase authenticated access</small></aside><main className="auth-main"><section className="auth-card"><span className="eyebrow teal">CAMPUS ACCESS</span><h2>Welcome back</h2>{!configured&&<div className="notice danger">Supabase is not configured. You can still open a demo preview below.</div>}{toast&&<div className="notice" role="status">{toast}</div>}<form className="stack-form" onSubmit={login}><label>Email<input type="email" name="email" value={email} onChange={event=>setEmail(event.target.value)} required placeholder="student@edu.lnbti.lk" autoComplete="email"/></label><label>Password<input type="password" name="password" required minLength="6" autoComplete="current-password"/></label><button className="btn btn-primary" disabled={busy}>{busyAction==='signin'&&<span className="button-spinner" aria-hidden="true"/>}{busyAction==='signin'?'Signing in…':'Sign in'}</button></form><button type="button" className="mini-link" onClick={requestPasswordReset} disabled={busy||!email.trim()}>{busyAction==='recovery'?'Sending reset link…':'Forgot password?'}</button>{import.meta.env.DEV&&<section className="demo-login" aria-label="Demo preview"><h3>Quick role preview</h3><div className="demo-login-buttons">{demoAccounts.map(account=><button className="btn btn-light" type="button" key={account.role} onClick={()=>onDemo(account.role)}>Preview {account.label}</button>)}</div><p>Preview only—no authentication or changes are saved.</p></section>}<div className="auth-divider">New student?</div><form className="stack-form" onSubmit={signup}><label>Full name<input name="full_name" required placeholder="Your name"/></label><label>Email<input type="email" name="email" required placeholder="student@edu.lnbti.lk"/></label><label>Password<input type="password" name="password" required minLength="6"/></label><button className="btn btn-light" disabled={busy}>{busyAction==='signup'&&<span className="button-spinner" aria-hidden="true"/>}{busyAction==='signup'?'Creating account…':'Create student account'}</button></form></section></main></div>;
}

function PasswordRecovery({onComplete}){
 const [password,setPassword]=useState(''),[confirmation,setConfirmation]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function submit(event){
  event.preventDefault();setError('');
  if(password.length<6){setError('Password must contain at least 6 characters.');return}
  if(password!==confirmation){setError('The passwords do not match.');return}
  setBusy(true);
  try{const {error:authError}=await supabase.auth.updateUser({password});if(authError)throw authError;onComplete()}
  catch(authError){setError(authError.message||'Could not update the password.')}
  finally{setBusy(false)}
 }
 return <div className="auth-wrap"><aside className="auth-panel"><div className="brand auth-brand"><span className="brand-mark">✦</span> UniEvents</div><div><span className="eyebrow">ACCOUNT SECURITY</span><h1>Choose a new password.</h1><p>Your reset link is validated by Supabase Auth.</p></div></aside><main className="auth-main"><section className="auth-card"><span className="eyebrow teal">PASSWORD RECOVERY</span><h2>Set a new password</h2>{error&&<div className="notice danger" role="alert">{error}</div>}<form className="stack-form" onSubmit={submit}><label>New password<input type="password" autoComplete="new-password" minLength="6" required value={password} onChange={event=>setPassword(event.target.value)}/></label><label>Confirm password<input type="password" autoComplete="new-password" minLength="6" required value={confirmation} onChange={event=>setConfirmation(event.target.value)}/></label><button className="btn btn-primary" disabled={busy}>{busy?'Updating…':'Update password'}</button></form></section></main></div>;
}

function Modal({children,onClose,big=false,qrcode=false}) {
 useEffect(()=>{
  const key=e=>{if(e.key==='Escape')onClose()};
  document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);
 },[onClose]);
 return <div className="modal-overlay" onMouseDown={e=>{if(e.target===e.currentTarget)onClose()}}><div className={`modal ${big?'big':''} ${qrcode?'qr-modal':''}`} role="dialog" aria-modal="true"><button className="modal-close" onClick={onClose} aria-label="Close">×</button>{children}</div></div>;
}

function StaffAssignmentRow({label,userId,accounts,onAssign,onRemove}) {
 const [selected,setSelected]=useState(userId||'');
 const current=accounts.find(account=>account.id===userId);
 useEffect(()=>setSelected(userId||''),[userId]);
 return <div className="staff-assignment-row">
  <div><h3>{label}</h3><p>{current?`Currently assigned: ${current.full_name}`:'Not assigned'}</p></div>
  <div className="staff-assignment-controls">
   <select aria-label={`${label} account`} value={selected} onChange={event=>setSelected(event.target.value)}>
    <option value="">Select an account</option>
    {accounts.map(account=><option key={account.id} value={account.id}>{account.full_name}</option>)}
   </select>
   <button type="button" className="btn btn-primary" disabled={!selected||selected===userId} onClick={()=>onAssign(selected)}>Save</button>
   {userId&&<button type="button" className="btn btn-danger" onClick={onRemove}>Remove</button>}
  </div>
 </div>;
}

function AccountRoleManager({accounts,roleAssignments,currentUserId,onAddRole,onUpdateRole,onRemoveRole,busy}) {
 const [query,setQuery]=useState('');
 const [page,setPage]=useState(0);
 const pageSize=25;
 const roleOptions=['student','committee','lecturer','authority','admin'];
 const rolesByUser=new Map();
 roleAssignments.forEach(assignment=>{
  const roles=rolesByUser.get(assignment.user_id)||[];
  roles.push(assignment.role);
  rolesByUser.set(assignment.user_id,roles);
 });
 const normalizedQuery=query.trim().toLowerCase();
 const filtered=accounts.filter(account=>{
  const roles=rolesByUser.get(account.id)||[];
  return `${account.full_name||''} ${account.id} ${roles.join(' ')}`.toLowerCase().includes(normalizedQuery);
 }).sort((a,b)=>(a.full_name||'').localeCompare(b.full_name||''));
 const pageCount=Math.max(1,Math.ceil(filtered.length/pageSize));
 const visible=filtered.slice(page*pageSize,(page+1)*pageSize);
 const changeSearch=value=>{setQuery(value);setPage(0)};
 return <section className="panel account-role-panel">
  <div className="account-role-heading"><div><h2>Account roles</h2><p>Search accounts to view, grant, change, or remove role assignments.</p></div><label className="account-role-search">Search accounts<input type="search" value={query} onChange={event=>changeSearch(event.target.value)} placeholder="Name, account ID, or role"/></label></div>
  <div className="account-role-list">
   <div className="account-role-header"><span>ACCOUNT</span><span>ASSIGNED ROLES AND ACTIONS</span></div>
   {visible.map(account=>{
    const assigned=rolesByUser.get(account.id)||[];
    const available=roleOptions.filter(role=>!assigned.includes(role));
    const isSelf=account.id===currentUserId;
    return <div className="account-role-row" key={account.id}>
     <div className="account-role-identity"><strong>{account.full_name||'Unnamed account'}</strong><small>{account.id}</small></div>
     <div className="account-role-actions">
      {assigned.length===0&&<span className="muted small">No roles assigned</span>}
      {assigned.map(role=><div className="account-role-item" key={role}>
       <span className="tag">{role}</span>
       <select aria-label={`Change ${role} role for ${account.full_name||account.id}`} value={role} disabled={busy||isSelf} onChange={event=>{const next=event.target.value;if(next)onUpdateRole(account,role,next)}}>
        <option value={role}>Change role…</option>
        {roleOptions.filter(option=>option!==role).map(option=><option key={option} value={option}>{option}</option>)}
       </select>
       <button className="btn btn-danger" type="button" disabled={busy||isSelf} onClick={()=>onRemoveRole(account,role)}>Remove</button>
      </div>)}
      {isSelf&&<span className="muted small">Your existing roles cannot be changed or removed here.</span>}
      {available.length>0?<form className="account-role-item account-role-add" onSubmit={event=>{event.preventDefault();const role=new FormData(event.currentTarget).get('role');if(role)onAddRole(account,String(role))}}>
       <label className="sr-only" htmlFor={`add-role-${account.id}`}>Add role for {account.full_name||account.id}</label>
       <select id={`add-role-${account.id}`} name="role" defaultValue={available[0]} disabled={busy}>{available.map(role=><option key={role} value={role}>{role}</option>)}</select>
       <button className="btn btn-light" type="submit" disabled={busy}>Add role</button>
      </form>:<span className="muted small">All roles assigned</span>}
     </div>
    </div>;
   })}
   {filtered.length===0&&<Empty title={accounts.length?'No matching accounts':'No accounts found'}/>}
  </div>
  <div className="account-role-footer"><span>{filtered.length} account{filtered.length===1?'':'s'}{normalizedQuery?' found': ''}</span><div className="buttons"><button className="btn btn-light" type="button" disabled={page===0} onClick={()=>setPage(value=>Math.max(0,value-1))}>Previous</button><span>Page {page+1} of {pageCount}</span><button className="btn btn-light" type="button" disabled={page+1>=pageCount} onClick={()=>setPage(value=>Math.min(pageCount-1,value+1))}>Next</button></div></div>
  <p className="account-role-note">Admins can grant additional roles to their own account. Existing own roles and the last administrator role cannot be removed or changed. Removing another account’s role does not remove a separately managed club staff assignment.</p>
 </section>;
}

function LoadingScreen(){
 return <main className="loading-screen" role="status" aria-live="polite">
  <div className="loading-content">
   <div className="loading-emblem" aria-hidden="true"><span>✦</span><i/></div>
   <span className="eyebrow teal">UNIEVENTS</span>
   <h1>Preparing your campus workspace</h1>
   <p>Loading your account and the latest campus activity.</p>
   <div className="loading-progress" role="progressbar" aria-label="Loading your workspace"><span/></div>
   <div className="loading-skeleton" aria-hidden="true"><i/><i/><i/></div>
  </div>
 </main>;
}

export default function App(){
 const [,rerender]=useState(0),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[roleSwitching,setRoleSwitching]=useState(false),[recoveryMode,setRecoveryMode]=useState(false),[demoMode,setDemoMode]=useState(false),[toast,setToast]=useState(null),[modal,setModal]=useState(null),[search,setSearch]=useState(''),[adminClubId,setAdminClubId]=useState(''),[clubContextId,setClubContextId]=useState(''),[auditSearch,setAuditSearch]=useState(''),[auditPageIndex,setAuditPageIndex]=useState(0);
 const [permissionSelection,setPermissionSelection]=useState({clubId:'',position:committeePositions[0]}),[legacyMigrationSeats,setLegacyMigrationSeats]=useState({});
 const roleSwitchingRef=useRef(false);
 const route=()=>location.hash.match(/^#\/([a-z-]+)/)?.[1]||'dashboard';
 const [page,setPage]=useState(route());
 useEffect(()=>{
  const onHash=()=>{setPage(route());setModal(null);window.scrollTo({top:0,behavior:'instant'})};
  window.addEventListener('hashchange',onHash);
  let mounted=true;
  async function boot(){
   const started=performance.now();
   try{
    await loadSession();
    if(mounted)rerender(x=>x+1);
    if(mounted&&store.user){
     const userId=store.user.id;
     refresh().then(()=>{
      if(mounted&&store.user?.id===userId)rerender(x=>x+1);
     }).catch(error=>{
      if(mounted)setToast({error:true,message:error.message||'Could not load campus data'});
     });
    }
   }catch(error){setToast({error:true,message:error.message||'Could not load your account'})}
   finally{
    const delay=Math.max(0,350-(performance.now()-started));
    window.setTimeout(()=>{if(mounted){setLoading(false);rerender(x=>x+1)}},delay);
   }
  }
  boot();
  if(supabase){const {data:{subscription}}=supabase.auth.onAuthStateChange(event=>{if(event==='PASSWORD_RECOVERY'){setRecoveryMode(true);setLoading(true);window.setTimeout(()=>{if(mounted)boot()},0)}else if(event==='SIGNED_IN'||event==='SIGNED_OUT'){if(event==='SIGNED_OUT')setRecoveryMode(false);window.setTimeout(()=>{if(mounted)boot()},0)}});return()=>{mounted=false;window.removeEventListener('hashchange',onHash);subscription.unsubscribe()}}
  return()=>{mounted=false;window.removeEventListener('hashchange',onHash)};
 },[]);
 const sync=async()=>{await refresh();rerender(x=>x+1)};
 const switchRole=async next=>{
  if(roleSwitchingRef.current||next===store.role)return;
  if(!store.roles.includes(next)){setToast({error:true,message:'Role not assigned'});return}
  const previous=store.role;
  roleSwitchingRef.current=true;
  setRoleSwitching(true);
  setModal(null);
  store.role=next;
  try{
   await refresh({strict:true});
   setPage('dashboard');
   if(location.hash!=='#/dashboard')location.hash='#/dashboard';
  }catch(error){
   store.role=previous;
   setToast({error:true,message:error?.message||'Could not switch roles'});
  }finally{
   roleSwitchingRef.current=false;
   setRoleSwitching(false);
  }
 };
 const transaction=async(fn,message)=>{
  if(demoMode){setToast({error:false,message:'Demo preview only — no changes were saved.'});return false}
  if(busy)return;setBusy(true);
  try{await fn();await sync();setModal(null);if(message)setToast({error:false,message});return true;}
  catch(e){console.error(e);setToast({error:true,message:e?.message||'Action failed'});return false;}
  finally{setBusy(false)}
 };
 const mutateAccountRole=(account,rpc,params,message)=>transaction(async()=>{
  await call(rpc,params);
  if(account.id===store.user?.id)await loadSession();
 },message);
 const confirmAdminChange=(title,summary,onConfirm)=>{
  if(demoMode){setToast({error:false,message:'Demo preview only — no changes were saved.'});return}
  setModal({type:'admin-confirm',title,summary,onConfirm});
 };
 const startDemoPreview=async selectedRole=>{
  if(!import.meta.env.DEV)return;
  setLoading(true);
  try{
   const {loadDemoPreview}=await import('./demo-preview.dev.js');
   loadDemoPreview(selectedRole);
   setDemoMode(true);
   setPage('dashboard');
   location.hash='#/dashboard';
  }catch(error){
   console.error(error);
   setToast({error:true,message:error.message||'Could not open demo preview'});
  }finally{setLoading(false)}
 };
 const exitDemoPreview=()=>{
  Object.assign(store,{user:null,profile:null,roles:[],role:null,clubs:[],proposals:[],events:[],versions:[],reviewers:[],decisions:[],comments:[],memberships:[],registrations:[],badges:[],badgeCandidates:[],badgeAuthorizations:[],badgeProfiles:[],payments:[],refundRequests:[],eventCancellations:[],notifications:[],proposalDocuments:[],emailDomains:[],committee:[],organizers:[],committeePermissions:[],approvalAuthorities:[],approvalRules:[],approvalRuleRecipients:[],accounts:[],accountRoles:[],attendance:[],auditLogs:[],auditError:null,selectedProposal:null});
  setDemoMode(false);setModal(null);setToast(null);setPage('dashboard');location.hash='#/dashboard';rerender(x=>x+1);
 };
 useEffect(()=>{if(toast){const id=setTimeout(()=>setToast(null),5200);return()=>clearTimeout(id)}},[toast]);
 if(loading)return <LoadingScreen />;
 if(recoveryMode&&store.user)return <PasswordRecovery onComplete={()=>{setRecoveryMode(false);setToast({error:false,message:'Password updated successfully.'})}}/>;
 if(!store.user)return <Auth onDemo={startDemoPreview}/>;
 const role=store.role||'student';
 const assignedClubIds=ownClubIds();
 const activeClubId=assignedClubIds.includes(clubContextId)?clubContextId:assignedClubIds[0]||'';
 const scopedClubIds=role==='committee'?(activeClubId?[activeClubId]:[]):assignedClubIds;
 const activeClubPositions=store.committee.filter(seat=>seat.club_id===activeClubId&&seat.user_id===store.user.id).map(seat=>seat.position_name);
 const committeeRoutePermissions={
  members:['club.members.view','club.members.manage'],
  registrations:['registration.view','registration.verify_external','registration.manage'],
  finance:['finance.view','finance.refund.approve','finance.reconcile','finance.export'],
  attendance:['attendance.scan','attendance.view'],
  badges:['badge.authorize'],
 };
 const roleNav=(nav[role]||nav.student).filter(([id])=>
  role!=='committee'||!committeeRoutePermissions[id]
   ||scopedClubIds.some(clubId=>committeeRoutePermissions[id].some(permission=>hasPermission(clubId,permission)))
 );
 const allowed=roleNav.some(x=>x[0]===page)?page:'dashboard';
 document.title=`${allowed.charAt(0).toUpperCase()+allowed.slice(1)} · UniEvents`;

 const action=async(kind,id,extra={})=>{
  if(kind==='logout'&&demoMode)return exitDemoPreview();
  if(demoMode){setToast({error:false,message:'Demo preview only — no changes were saved.'});return}
  switch(kind){
   case'logout':return transaction(async()=>{await supabase.auth.signOut();store.user=null;store.role=null;location.hash='#/dashboard'},'Signed out');
   case'submit':return transaction(()=>call('submit_proposal',{p_proposal:id}),'Proposal submitted to lecturer');
   case'publish':return transaction(()=>call('publish_proposal',{p_proposal:id}),'Event published');
   case'join':return transaction(()=>call('apply_membership',{p_club:id}),'Membership application submitted');
   case'register':return transaction(()=>call('register_event_with_answers',{p_proposal:id,p_answers:extra.answers||{}}),'Registration submitted');
   case'external-register':return transaction(()=>call('claim_external_registration',{p_proposal:id,p_external_reference:extra.reference}),'External registration submitted for verification');
   case'member-approve':return transaction(()=>call('decide_membership',{p_membership:id,p_approve:true}),'Membership approved');
   case'member-reject':return transaction(()=>call('decide_membership',{p_membership:id,p_approve:false}),'Membership rejected');
   case'checkout':return transaction(()=>checkout(extra.kind,id));
   case'notification-read':return transaction(()=>call('mark_notification_read',{p_notification:id}));
   case'notification-read-all':return transaction(()=>call('mark_all_notifications_read'), 'Notifications marked as read');
  }
 };

 const dashboard=()=>{
  if(role==='student')return <><section className="hero"><div><span className="eyebrow">YOUR CAMPUS. YOUR COMMUNITY.</span><h1>Find your next campus moment.</h1><p>Explore events, meet your people, and celebrate your participation.</p><a className="btn btn-primary" href="#/explore">Explore events</a></div></section><div className="metrics"><Metric n={store.events.length} label="Published events"/><Metric n={store.registrations.filter(r=>r.user_id===store.user.id).length} label="My registrations"/><Metric n={store.memberships.filter(m=>m.user_id===store.user.id&&m.status==='active').length} label="My clubs"/><Metric n={store.badges.filter(b=>b.user_id===store.user.id).length} label="Earned badges"/></div><h2>Featured campus events</h2><div className="event-grid">{store.events.slice(0,3).map(EventCard)}</div></>;
  const own=scopedClubIds;
  const queue=role==='committee'?store.proposals.filter(p=>own.includes(p.club_id)):role==='lecturer'?store.proposals.filter(p=>store.clubs.some(c=>c.id===p.club_id&&c.lecturer_id===store.user.id)):role==='authority'?store.proposals.filter(p=>p.status==='authority_pending'&&store.reviewers.some(r=>r.proposal_id===p.id&&r.version===p.current_version&&r.user_id===store.user.id)):store.proposals;
  return <><section className="hero"><div><span className="eyebrow">UNIVERSITY EVENTS OPERATIONS</span><h1>Welcome, {store.profile?.full_name?.split(' ')[0]||'there'}.</h1><p>Manage the campus event lifecycle with clarity and accountability.</p></div></section><div className="metrics"><Metric n={store.clubs.length} label="University clubs"/><Metric n={queue.length} label="Proposals in scope"/><Metric n={queue.filter(p=>['lecturer_pending','authority_pending'].includes(p.status)).length} label="Under review"/><Metric n={store.events.length} label="Published events"/></div><ProposalTable data={queue.slice(0,6)}/></>;
 };

 function Metric({n,label}){return <div className="metric"><span className="metric-num">{n}</span><span className="metric-label">{label}</span></div>}
 function EventCard(e){
  const v=e.version||vOf(e);
  return <article className="event-card" key={e.id}><div className="event-inner"><span className="eyebrow teal">{clubOf(e.club_id)?.name||'Campus club'}</span><h3>{v?.title}</h3><p className="muted small">{date(v?.starts_at)} · {time(v?.starts_at)}</p><p className="muted small">{v?.venue} · {money(v?.fee_cents)}</p><button className="btn btn-light" onClick={()=>setModal({type:'event',id:e.id})}>View event</button></div></article>;
 }
 function ProposalTable({data}){
  return <div className="table-card"><table><thead><tr><th>EVENT PROPOSAL</th><th>CLUB</th><th>VERSION</th><th>STATUS</th><th></th></tr></thead><tbody>{data.map(p=><tr key={p.id}><td><strong>{vOf(p)?.title||'—'}</strong></td><td>{clubOf(p.club_id)?.name}</td><td>V{p.current_version}</td><td><Status s={p.status}/></td><td><button className="mini-link" onClick={()=>setModal({type:'proposal',id:p.id})}>Open</button></td></tr>)}</tbody></table>{data.length===0&&<Empty title="No proposals here yet"/>}</div>;
 }

 const explore=()=>{const query=search.toLowerCase();const events=store.events.filter(e=>`${e.version?.title||''} ${clubOf(e.club_id)?.name||''}`.toLowerCase().includes(query));return <><div className="page-head"><h1>Explore events</h1></div><div className="toolbar"><label className="search"><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search events or clubs"/></label><span className="mini-tag">{events.length} published events</span></div><div className="event-grid">{events.map(EventCard)}{events.length===0&&<Empty title="No events found"/>}</div></>};
 const clubsPage=()=> <><div className="page-head"><h1>University clubs</h1></div><div className="club-grid">{store.clubs.map((c,i)=>{const m=store.memberships.find(x=>x.club_id===c.id&&x.user_id===store.user.id);return <article className="club-card" key={c.id}><div className={`club-banner color-${i%4} ${c.logo_path?'has-logo':''}`}>{c.logo_path?<img className="club-logo-image" src={clubLogoUrl(c)} alt={`${c.name} logo`} loading="lazy"/>:<span className="club-graphic">✦</span>}</div><div className="club-card-body"><span className="eyebrow teal">{c.category}</span><h3>{c.name}</h3><p>{c.description}</p><div className="flex-between"><strong className="price">{money(c.membership_fee_cents)} membership</strong>{m?<Status s={m.status}/>:role!=='admin'&&<button className="btn btn-light" onClick={()=>action('join',c.id)}>Apply to join</button>}</div></div></article>})}{store.clubs.length===0&&<Empty title="No clubs created"/>}</div></>;
 const myEvents=()=>{const mine=store.registrations.filter(r=>r.user_id===store.user.id);return <><div className="page-head"><h1>My events</h1><p>Registration verification, payment, and attendance are shown separately.</p></div><div className="panel">{mine.map(r=>{const p=store.proposals.find(x=>x.id===r.proposal_id);const v=store.versions.find(version=>version.proposal_id===r.proposal_id&&version.version===r.version)||vOf(p);const payment=store.payments.filter(order=>order.kind==='registration'&&order.reference_id===r.id).sort((a,b)=>new Date(b.created_at)-new Date(a.created_at))[0];const attendance=store.attendance.find(record=>record.proposal_id===r.proposal_id&&record.user_id===store.user.id);return <div className="list-item" key={r.id}><div><strong>{v?.title||'Event'}</strong><p>{date(v?.starts_at)} · {v?.venue}</p><p>Registration <Status s={r.status}/>{r.verification_status!=='not_required'&&<> · External verification <Status s={r.verification_status}/></>} {payment&&<> · Payment <Status s={payment.status}/></>} · Attendance <Status s={attendance?'verified':'not_recorded'}/></p>{r.verification_reason&&<p className="muted small">{r.verification_reason}</p>}</div>{r.status==='payment_due'?<span className="muted small">Payment setup is pending; checkout is currently disabled.</span>:r.status==='registered'&&r.verification_status!=='pending'?<span className="muted small">Open the UniEvents mobile app for your event-specific attendance pass.</span>:r.verification_status==='pending'?<span className="muted small">Awaiting committee verification.</span>:null}</div>})}{mine.length===0&&<Empty title="No registrations yet"/>}</div></>};
 const myMemberships=()=>{const mine=store.memberships.filter(m=>m.user_id===store.user.id);return <><div className="page-head"><h1>My memberships</h1><p>Current and past membership requests for your clubs.</p></div><div className="panel">{mine.map(m=><div className="list-item" key={m.id}><div><strong>{clubOf(m.club_id)?.name||'Club'}</strong><p>Requested {date(m.created_at)} · <Status s={m.status}/></p></div>{m.status==='payment_due'&&<a className="btn btn-light" href="#/payments">Complete payment</a>}</div>)}{mine.length===0&&<Empty title="No club memberships yet" subtitle="Browse the club directory to find a club."/>}</div></>};
 const payments=()=>{
  const dues=[
   ...store.memberships.filter(m=>m.user_id===store.user.id&&m.status==='payment_due')
    .map(m=>({kind:'membership',ref:m.id,label:clubOf(m.club_id)?.name,fee:clubOf(m.club_id)?.membership_fee_cents})),
   ...store.registrations.filter(r=>r.user_id===store.user.id&&r.status==='payment_due')
    .map(r=>({kind:'registration',ref:r.id,label:vOf(store.proposals.find(p=>p.id===r.proposal_id))?.title,fee:vOf(store.proposals.find(p=>p.id===r.proposal_id))?.fee_cents}))
  ];
  const formatAmount=(code,minor)=>{try{return new Intl.NumberFormat(undefined,{style:'currency',currency:String(code||'USD').toUpperCase()}).format((minor||0)/100)}catch{return `${String(code||'USD').toUpperCase()} ${((minor||0)/100).toFixed(2)}`}};
  const history=store.payments.filter(order=>order.user_id===store.user.id).sort((a,b)=>new Date(b.created_at)-new Date(a.created_at));
  const refunds=store.refundRequests.filter(refund=>history.some(order=>order.id===refund.payment_order_id));
  return <><div className="page-head"><h1>Payments</h1></div>
   <div className="notice">Paid checkout is disabled until the university selects and configures a payment provider. No payment will be collected.</div>
   {dues.length>0&&<div className="panel"><h2>Payments awaiting setup</h2>{dues.map(item=><div className="list-item" key={`${item.kind}-${item.ref}`}><div><strong>{item.label}</strong><p>{item.kind} · {money(item.fee)}</p></div><Status s="payment_due"/></div>)}</div>}
   <div className="panel"><h2>Payment history</h2>{history.length>0&&<div className="table-card"><table><thead><tr><th>ITEM</th><th>AMOUNT</th><th>STATUS</th><th>CREATED</th><th>CONFIRMED</th></tr></thead><tbody>{history.map(order=>{const label=order.kind==='membership'?clubOf(store.memberships.find(m=>m.id===order.reference_id)?.club_id)?.name:vOf(store.proposals.find(p=>p.id===store.registrations.find(r=>r.id===order.reference_id)?.proposal_id))?.title;return <tr key={order.id}><td>{label||`${order.kind} payment`}<small className="muted"> · {order.kind}</small></td><td>{formatAmount(order.currency,order.amount_cents)}</td><td><Status s={order.status}/></td><td>{date(order.created_at)}</td><td>{order.paid_at?date(order.paid_at):'—'}</td></tr>})}</tbody></table></div>}{history.length===0&&<Empty title="No payment attempts yet"/>}<p className="muted small">History shows the latest records available to your account.</p></div>
   <div className="panel"><h2>Refund status</h2>{refunds.map(refund=><div className="list-item" key={refund.id}><div><strong>{vOf(store.proposals.find(p=>p.id===refund.proposal_id))?.title||'Cancelled event'}</strong><p>{formatAmount(refund.currency,refund.amount_minor)} · {refund.cancellation_reason}</p><p className="muted small">{refund.review_reason||'Refund status is based on the recorded officer/provider outcome.'}</p></div><div><Status s={refund.status}/><p className="muted small">Gateway: {refund.provider_status}</p></div></div>)}{refunds.length===0&&<Empty title="No refund activity"/>}</div>
  </>;
 };
 const badges=()=>role==='student'?<><div className="page-head"><h1>Digital badges</h1></div><div className="badge-grid">{store.badges.filter(b=>b.user_id===store.user.id&&b.authorized_by).map(b=>{const v=vOf(store.proposals.find(p=>p.id===b.proposal_id));return <div className="badge-card" key={b.id}><span className="badge-emblem">✦</span><h3>{v?.title||'Campus event'}</h3><p>Earned {date(b.issued_at)}</p><p>Authorized by {store.badgeProfiles.find(profile=>profile.id===b.authorized_by)?.full_name||'an authorized committee member'}</p></div>})}{store.badges.filter(b=>b.user_id===store.user.id&&b.authorized_by).length===0&&<Empty title="No badges yet"/>}</div></>:<><div className="page-head"><div><h1>Badge authorization</h1><p>{clubOf(activeClubId)?.name||'Selected club'} · Attendance creates eligibility only; an authorized decision is required to issue a badge.</p></div></div><div className="panel">{store.badgeCandidates.filter(candidate=>candidate.status==='pending'&&scopedClubIds.some(clubId=>store.proposals.some(proposal=>proposal.id===candidate.proposal_id&&proposal.club_id===clubId))).map(candidate=>{const proposal=store.proposals.find(item=>item.id===candidate.proposal_id),student=store.badgeProfiles.find(profile=>profile.id===candidate.user_id);return <div className="list-item" key={candidate.id}><div><strong>{student?.full_name||'Student'}</strong><p>{vOf(proposal)?.title||'Campus event'} · Candidate since {date(candidate.created_at)}</p></div><div className="buttons"><button className="btn btn-primary" onClick={()=>setModal({type:'badge-decision',candidate,approve:true})}>Approve badge</button><button className="btn btn-danger" onClick={()=>setModal({type:'badge-decision',candidate,approve:false})}>Reject</button></div></div>})}{store.badgeCandidates.filter(candidate=>candidate.status==='pending'&&scopedClubIds.some(clubId=>store.proposals.some(proposal=>proposal.id===candidate.proposal_id&&proposal.club_id===clubId))).length===0&&<Empty title="No badge candidates pending"/>}</div></>;
 function financePage(){
  const rows=store.refundRequests.filter(refund=>scopedClubIds.includes(refund.club_id));
  const transactions=store.payments.filter(order=>{
   const membership=order.kind==='membership'?store.memberships.find(item=>item.id===order.reference_id):null;
   const registration=order.kind==='registration'?store.registrations.find(item=>item.id===order.reference_id):null;
   const proposal=registration&&store.proposals.find(item=>item.id===registration.proposal_id);
   const clubId=membership?.club_id||proposal?.club_id;
   return clubId&&scopedClubIds.includes(clubId)&&hasPermission(clubId,'finance.view');
  });
  const canReview=rows.some(refund=>hasPermission(refund.club_id,'finance.refund.approve'));
  const format=(currency,minor)=>`${String(currency||'USD').toUpperCase()} ${(Number(minor||0)/100).toFixed(2)}`;
  if(!scopedClubIds.some(clubId=>hasPermission(clubId,'finance.view')||hasPermission(clubId,'finance.refund.approve')))return <Empty title="Finance permission required"/>;
  return <><div className="page-head"><h1>Club finance · {clubOf(activeClubId)?.name||'Selected club'}</h1><p>Payment facts are read-only. Refund approval is separate from provider processing.</p></div><div className="panel"><h2>Transactions</h2>{transactions.map(order=>{const registration=order.kind==='registration'&&store.registrations.find(item=>item.id===order.reference_id);const proposal=registration&&store.proposals.find(item=>item.id===registration.proposal_id);const membership=order.kind==='membership'&&store.memberships.find(item=>item.id===order.reference_id);return <div className="list-item" key={order.id}><div><strong>{order.kind==='membership'?clubOf(membership?.club_id)?.name:vOf(proposal)?.title||'Event registration'}</strong><p>{format(order.currency,order.amount_cents)} · {date(order.created_at)}</p></div><Status s={order.status}/></div>})}{transactions.length===0&&<Empty title="No transactions in this club"/>}</div><div className="panel"><h2>Refund requests</h2>{rows.map(refund=><div className="list-item" key={refund.id}><div><strong>{vOf(store.proposals.find(proposal=>proposal.id===refund.proposal_id))?.title||'Cancelled event'}</strong><p>{format(refund.currency,refund.amount_minor)} · {refund.cancellation_reason}</p><p>Gateway: <Status s={refund.provider_status}/>{refund.review_reason&&<> · {refund.review_reason}</>}</p></div><div className="buttons"><Status s={refund.status}/>{refund.status==='awaiting_approval'&&hasPermission(refund.club_id,'finance.refund.approve')&&<><button className="btn btn-primary" onClick={()=>setModal({type:'refund-decision',refund,approve:true})}>Approve</button><button className="btn btn-danger" onClick={()=>setModal({type:'refund-decision',refund,approve:false})}>Reject</button></>}</div></div>)}{rows.length===0&&<Empty title="No refund requests"/>}</div>{canReview&&<p className="muted small">Approved refunds remain pending until an enabled provider confirms the outcome.</p>}</>;
 }
 function registrationsPage(){
  const rows=store.registrations.filter(registration=>{
   const proposal=store.proposals.find(item=>item.id===registration.proposal_id);
   return proposal&&scopedClubIds.includes(proposal.club_id)
    &&(hasPermission(proposal.club_id,'registration.view')
     ||hasPermission(proposal.club_id,'registration.verify_external')
     ||hasPermission(proposal.club_id,'registration.manage'));
  });
  return <><div className="page-head"><h1>Event registrations</h1><p>{clubOf(activeClubId)?.name||'Selected club'} · External submissions require a recorded decision.</p></div><div className="panel">
   {rows.map(registration=>{
    const proposal=store.proposals.find(item=>item.id===registration.proposal_id);
    const version=store.versions.find(item=>item.proposal_id===registration.proposal_id&&item.version===registration.version);
    const student=store.badgeProfiles.find(profile=>profile.id===registration.user_id);
    const canVerify=registration.verification_status==='pending'&&hasPermission(proposal.club_id,'registration.verify_external');
    return <article className="list-item" key={registration.id}><div><strong>{student?.full_name||'Student'} · {version?.title||'Event'}</strong><p><Status s={registration.status}/> · Verification <Status s={registration.verification_status}/></p>{registration.external_reference&&<p>External reference: {registration.external_reference}</p>}{hasPermission(proposal.club_id,'registration.view')&&Object.keys(registration.form_answers||{}).length>0&&<details><summary>Registration answers</summary><pre>{JSON.stringify(registration.form_answers,null,2)}</pre></details>}{registration.verification_reason&&<p className="muted small">{registration.verification_reason}</p>}</div>{canVerify&&<div className="buttons"><button className="btn btn-primary" onClick={()=>setModal({type:'external-registration-decision',registration,verified:true})}>Verify</button><button className="btn btn-danger" onClick={()=>setModal({type:'external-registration-decision',registration,verified:false})}>Not verified</button></div>}</article>;
   })}
   {rows.length===0&&<Empty title="No event registrations"/>}
  </div></>;
 }
 function profilePage(){return <><div className="page-head"><h1>My profile</h1></div><div className="panel profile-panel"><h2>{store.profile?.full_name}</h2><p>{store.user.email}</p><div className="flex-row">{store.roles.map(r=><Status key={r} s={r}/>)}</div></div></>}

 function proposalPage(){const own=scopedClubIds;const data=role==='admin'?store.proposals:store.proposals.filter(p=>own.includes(p.club_id));return <><div className="page-head flex-between"><div><h1>Event proposals</h1>{role==='committee'&&<p>{clubOf(activeClubId)?.name||'Select a club'} · {activeClubPositions.join(', ')}</p>}</div>{role==='committee'&&own.some(clubId=>hasPermission(clubId,'event.create'))&&<button className="btn btn-primary" onClick={()=>setModal({type:'proposal-form'})}>+ New proposal</button>}</div><ProposalTable data={data}/></>}
 function auditPage(){const pageSize=20,normalized=auditSearch.trim().toLowerCase(),filtered=store.auditLogs.filter(entry=>`${entry.actor_id||''} ${entry.entity_type} ${entry.entity_id} ${entry.action} ${JSON.stringify(entry.details||{})}`.toLowerCase().includes(normalized)),pageCount=Math.max(1,Math.ceil(filtered.length/pageSize)),visible=filtered.slice(auditPageIndex*pageSize,(auditPageIndex+1)*pageSize);return <><div className="page-head"><div><h1>Audit history</h1><p>Latest 100 records available to administrators. Search filters this loaded set.</p></div></div>{store.auditError&&<div className="notice danger" role="alert">Audit history could not be loaded: {store.auditError}</div>}<div className="toolbar"><label className="search"><input type="search" value={auditSearch} onChange={event=>{setAuditSearch(event.target.value);setAuditPageIndex(0)}} placeholder="Search actor, action, resource, or details"/></label><span className="mini-tag">{filtered.length} records</span></div><div className="table-card"><table><thead><tr><th>TIME</th><th>ACTOR</th><th>ACTION</th><th>RESOURCE</th><th>DETAILS</th></tr></thead><tbody>{visible.map(entry=><tr key={entry.id}><td>{new Date(entry.created_at).toLocaleString()}</td><td>{entry.actor_id||'System'}</td><td>{entry.action.replaceAll('_',' ')}</td><td>{entry.entity_type} · {entry.entity_id}</td><td><code>{JSON.stringify(entry.details||{})}</code>{entry.entity_type==='proposal'&&<button type="button" className="mini-link" onClick={()=>setModal({type:'proposal',id:entry.entity_id})}>Open proposal</button>}</td></tr>)}</tbody></table>{visible.length===0&&<Empty title={store.auditError?'Audit history unavailable':store.auditLogs.length?'No matching audit records':'No audit records available'}/>}</div><div className="account-role-footer"><span>Page {auditPageIndex+1} of {pageCount}</span><div className="buttons"><button className="btn btn-light" disabled={auditPageIndex===0} onClick={()=>setAuditPageIndex(value=>Math.max(0,value-1))}>Previous</button><button className="btn btn-light" disabled={auditPageIndex+1>=pageCount} onClick={()=>setAuditPageIndex(value=>Math.min(pageCount-1,value+1))}>Next</button></div></div></>}
 function notificationsPage(){
  const unread=store.notifications.filter(item=>!item.read_at).length;
  async function open(item){
   if(!item.read_at&&!await transaction(()=>call('mark_notification_read',{p_notification:item.id})))return;
   if(item.entity_type==='proposal')setModal({type:'proposal',id:item.entity_id});
  }
  return <>
   <div className="page-head flex-between">
    <div><h1>Notifications</h1><p>{unread} unread · Recent account activity and decisions.</p></div>
    {unread>0&&<button className="btn btn-light" onClick={()=>action('notification-read-all')}>Mark all as read</button>}
   </div>
   <div className="panel notification-list">
    {store.notifications.map(item=><article className={`notification-item ${item.read_at?'is-read':''}`} key={item.id}>
     <div><strong>{item.summary}</strong><p>{date(item.created_at)} · {time(item.created_at)}</p></div>
     <div className="buttons">
      {item.entity_type==='proposal'&&<button className="btn btn-light" onClick={()=>open(item)}>Open proposal</button>}
      {!item.read_at&&<button className="mini-link" onClick={()=>action('notification-read',item.id)}>Mark read</button>}
     </div>
    </article>)}
    {store.notifications.length===0&&<Empty title="No notifications yet" subtitle="Updates about reviews, memberships, registrations, payments, and badges will appear here."/>}
   </div>
  </>;
 }
 function membersPage(){const data=store.memberships.filter(m=>scopedClubIds.includes(m.club_id));return <><div className="page-head"><h1>Membership requests</h1><p>{clubOf(activeClubId)?.name||'Selected club'}</p></div><div className="panel">{data.map(m=><div className="list-item" key={m.id}><div><strong>{clubOf(m.club_id)?.name}</strong><p><Status s={m.status}/></p></div>{m.status==='pending'&&hasPermission(m.club_id,'club.members.manage')&&<div className="buttons"><button className="btn btn-primary" onClick={()=>action('member-approve',m.id)}>Approve</button><button className="btn btn-danger" onClick={()=>action('member-reject',m.id)}>Reject</button></div>}</div>)}{data.length===0&&<Empty title="No membership requests"/>}</div></>}
 function reviewsPage(){const data=role==='lecturer'?store.proposals.filter(p=>p.status==='lecturer_pending'&&store.clubs.some(c=>c.id===p.club_id&&c.lecturer_id===store.user.id)):store.proposals.filter(p=>p.status==='authority_pending'&&store.reviewers.some(r=>r.proposal_id===p.id&&r.version===p.current_version&&r.user_id===store.user.id));return <><div className="page-head"><h1>{role==='lecturer'?'Lecturer review':'Higher authority review'}</h1></div><ProposalTable data={data}/></>}
 function permissionsPage(){const positions=store.committee.filter(seat=>seat.user_id===store.user.id&&scopedClubIds.includes(seat.club_id));return <><div className="page-head"><div><h1>My role &amp; permissions</h1><p>Permissions depend on your current position and club. An unlisted permission is not granted.</p></div></div>{positions.map(seat=><section className="panel" key={`${seat.club_id}-${seat.position_name}`}><h2>{clubOf(seat.club_id)?.name} · {seat.position_name}</h2><ul className="permission-summary">{committeePermissions.map(([key,label])=><li key={key}><span>{label}</span><Status s={hasPermission(seat.club_id,key)?'enabled':'disabled'}/></li>)}</ul></section>)}{positions.length===0&&<Empty title="No active committee positions"/>}</>}
 function adminPage(){return <>
  <div className="page-head"><div><h1>Administration</h1><p>Manage clubs, staff assignments, and account roles.</p></div></div>
  <section className="admin-section"><div className="admin-section-heading"><span>01</span><div><h2>Club profiles</h2><p>Create a club or update an existing club’s details and logo.</p></div></div><div className="admin-grid"><AdminCreateClub/><AdminEditClub/></div></section>
  <section className="admin-section"><div className="admin-section-heading"><span>02</span><div><h2>Club staff</h2><p>Assign the five named committee positions and migrate legacy organizers explicitly.</p></div></div><AdminClubAssign/><LegacyOrganizerMigrations/></section>
  <section className="admin-section">
   <div className="admin-section-heading"><span>03</span><div><h2>Account access</h2><p>Manage system roles independently from club-scoped committee positions.</p></div></div>
   <AccountRoleManager
    accounts={store.accounts}
    roleAssignments={store.accountRoles}
    currentUserId={store.user.id}
    busy={busy}
    onAddRole={(account,accountRole)=>confirmAdminChange('Confirm role grant',`Grant the ${accountRole} role to ${account.full_name||'this account'}?`,()=>mutateAccountRole(account,'admin_assign_role',{p_user:account.id,p_role:accountRole},'Role assigned'))}
    onUpdateRole={(account,oldRole,newRole)=>confirmAdminChange('Confirm role change',`Replace ${account.full_name||'this account'}’s ${oldRole} role with ${newRole}?`,()=>mutateAccountRole(account,'admin_update_user_role',{p_user:account.id,p_old_role:oldRole,p_new_role:newRole},'Role updated'))}
    onRemoveRole={(account,accountRole)=>confirmAdminChange('Confirm role removal',`Remove the ${accountRole} role from ${account.full_name||'this account'}?`,()=>mutateAccountRole(account,'admin_remove_user_role',{p_user:account.id,p_role:accountRole},'Role removed'))}
   />
   <div className="panel"><h2>Higher-authority routing</h2><p>Coordinator approval is routed by the active event-category and LKR-budget rules below. Missing matches or inactive recipients create a visible routing exception.</p></div>
  </section>
  <section className="admin-section"><div className="admin-section-heading"><span>04</span><div><h2>Committee permissions</h2><p>All catalogued permissions are enabled by default for each club position; Admins can revoke individual grants.</p></div></div><AdminPermissionMatrix/></section>
  <section className="admin-section"><div className="admin-section-heading"><span>05</span><div><h2>Authority routing rules</h2><p>Every proposal version snapshots matching category/budget rules and its assigned reviewers.</p></div></div><AdminAuthorityRules/></section>
  <section className="admin-section"><div className="admin-section-heading"><span>06</span><div><h2>University email domains</h2><p>New accounts and email changes are limited to institution-approved domains.</p></div></div><AdminEmailDomains/></section>
 </>}
 function attendancePage(){const clubs=scopedClubIds,canScan=clubs.some(clubId=>hasPermission(clubId,'attendance.scan')),canView=clubs.some(clubId=>hasPermission(clubId,'attendance.view')),records=store.attendance.filter(record=>store.proposals.some(proposal=>proposal.id===record.proposal_id&&clubs.includes(proposal.club_id)));if(role!=='committee'||(!canScan&&!canView))return <Empty title="Attendance permission required"/>;return <><div className="page-head"><h1>Attendance · {clubOf(activeClubId)?.name||'Selected club'}</h1></div>{canScan&&<section className="panel"><h2>Check in a participant</h2><form className="stack-form" onSubmit={async e=>{e.preventDefault();const f=new FormData(e.currentTarget);await transaction(async()=>{const result=await call('scan_attendance_token',{p_token:String(f.get('token')).trim()});if(!result.ok)throw Error('Check-in failed')},'Attendance verified')}}><label>One-time token<input name="token" required/></label><button className="btn btn-primary">Verify check-in</button></form></section>}{canView&&<section className="panel"><h2>Verified attendance</h2>{records.map(record=>{const proposal=store.proposals.find(item=>item.id===record.proposal_id);return <div className="list-item" key={record.id}><div><strong>{vOf(proposal)?.title||'Event'}</strong><p>Student {record.user_id} · Verified {new Date(record.checked_at).toLocaleString()}</p></div><Status s="verified"/></div>})}{records.length===0&&<Empty title="No attendance records yet"/>}</section>}</>}
 function calendarPage(){const now=new Date(),year=now.getFullYear(),month=now.getMonth(),first=new Date(year,month,1).getDay(),total=new Date(year,month+1,0).getDate();const cells=[];for(let d=1;d<=total;d++){const events=store.events.filter(e=>{const dt=new Date(e.version.starts_at);return dt.getFullYear()===year&&dt.getMonth()===month&&dt.getDate()===d});cells.push(<div className="cal-day" key={d}><strong>{d}</strong>{events.map(e=><button key={e.id} className="cal-event" onClick={()=>setModal({type:'event',id:e.id})}>{e.version.title}</button>)}</div>)}return <><div className="page-head"><h1>Event calendar</h1></div><div className="panel calendar-panel"><h2>{now.toLocaleDateString('en',{month:'long',year:'numeric'})}</h2><div className="cal-grid" style={{gridTemplateColumns:'repeat(7,1fr)',paddingLeft:`${first*0}px`}}>{Array.from({length:first}).map((_,i)=><div className="cal-blank" key={i}/>)}{cells}</div></div></>}

 function AdminCreateClub(){
  const [logo,setLogo]=useState(null),[preview,setPreview]=useState('');
  useEffect(()=>{if(!logo){setPreview('');return}const url=URL.createObjectURL(logo);setPreview(url);return()=>URL.revokeObjectURL(url)},[logo]);
  function submit(e){
   e.preventDefault();
   const f=new FormData(e.currentTarget),name=String(f.get('name')).trim(),category=String(f.get('category')||'General'),description=String(f.get('description')||''),fee=Number(f.get('fee'));
   confirmAdminChange('Confirm club creation',`Create “${name}” in ${category} with a ${money(fee)} membership fee${logo?' and the selected logo':''}?`,()=>transaction(async()=>{
    let logoPath=null;
    if(logo){
     const extension=logo.type==='image/png'?'png':logo.type==='image/webp'?'webp':'jpg';
     logoPath=`${crypto.randomUUID()}.${extension}`;
     const {error:uploadError}=await supabase.storage.from('club-logos').upload(logoPath,logo,{cacheControl:'3600',contentType:logo.type,upsert:false});
     if(uploadError)throw new Error(`Logo upload failed: ${uploadError.message}`);
    }
    try{
     return await call('admin_create_club_with_logo',{p_name:name,p_description:description,p_category:category,p_fee_cents:fee,p_logo_path:logoPath});
    }catch(error){
     if(logoPath){
      const {error:cleanupError}=await supabase.storage.from('club-logos').remove([logoPath]);
      if(cleanupError)throw new Error(`${error.message}. Uploaded logo cleanup failed: ${cleanupError.message}`);
     }
     throw error;
    }
   },'Club created'));
  }
  function chooseLogo(e){
   const file=e.target.files?.[0]||null;
   if(file&&(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>5*1024*1024)){
    setLogo(null);e.target.value='';setToast({error:true,message:'Choose a PNG, JPEG, or WebP image up to 5 MB.'});return;
   }
   setLogo(file);
  }
  return <section className="panel"><h2>Create university club</h2><form id="create-club" className="stack-form" onSubmit={submit}><label>Club name<input name="name" required minLength="2"/></label><label>Category<input name="category" defaultValue="General"/></label><label>Description<textarea name="description"/></label><label>Membership fee (USD cents)<input name="fee" type="number" min="0" defaultValue="0"/></label><label>Club logo (optional)<input type="file" accept="image/png,image/jpeg,image/webp" onChange={chooseLogo}/></label>{preview&&<img className="club-logo-preview" src={preview} alt="Selected club logo preview"/>}<button className="btn btn-primary">Review change</button></form></section>
 }
 function AdminPermissionMatrix(){
  const clubId=store.clubs.some(club=>club.id===permissionSelection.clubId)?permissionSelection.clubId:store.clubs[0]?.id||'';
  const position=permissionSelection.position;
  return <section className="panel permission-matrix">
   <div className="staff-club-picker"><label>Club<select value={clubId} onChange={event=>setPermissionSelection(current=>({...current,clubId:event.target.value}))}>{store.clubs.map(club=><option key={club.id} value={club.id}>{club.name}</option>)}</select></label><label>Committee position<select value={position} onChange={event=>setPermissionSelection(current=>({...current,position:event.target.value}))}>{committeePositions.map(name=><option key={name}>{name}</option>)}</select></label></div>
   {!clubId?<Empty title="Create a club before configuring permissions"/>:<div className="permission-matrix-list">{committeePermissions.map(([permission,label])=><label className="admin-checkbox" key={permission}><input type="checkbox" checked={hasPermission(clubId,permission)} disabled={busy} onChange={event=>transaction(()=>call('admin_set_committee_permission',{p_club:clubId,p_position:position,p_permission:permission,p_enabled:event.target.checked}),`Permission ${event.target.checked?'granted':'removed'}`)}/><span><strong>{label}</strong><small>{permission}</small></span></label>)}</div>}
   <p className="muted small">Grants apply only to this position in this club. Remove sensitive actions here when a position should not perform them.</p>
  </section>;
 }
 function AdminEmailDomains(){
  const [value,setValue]=useState(store.emailDomains.map(item=>item.domain).join(', '));
  useEffect(()=>setValue(store.emailDomains.map(item=>item.domain).join(', ')),[store.emailDomains]);
  function save(event){
   event.preventDefault();
   const domains=[...new Set(value.split(/[,\s]+/).map(domain=>domain.trim().replace(/^@/,'').toLowerCase()).filter(Boolean))];
   transaction(()=>call('admin_set_email_domains',{p_domains:domains}),'University email domains saved');
  }
  return <section className="panel"><form className="stack-form" onSubmit={save}><label>Allowed domains<input value={value} onChange={event=>setValue(event.target.value)} placeholder="edu.lnbti.lk" required/></label><p className="muted small">Separate multiple domains with commas or spaces. Do not include an @ symbol. The server enforces this list during account creation and email changes.</p><div className="flex-row">{store.emailDomains.map(item=><Status key={item.domain} s={item.domain}/>)}</div><button type="submit" className="btn btn-primary" disabled={busy}>Save allowed domains</button></form></section>;
 }
 function AdminAuthorityRules(){
  const [selected,setSelected]=useState([]);
  const authorityIds=new Set(store.accountRoles.filter(item=>item.role==='authority').map(item=>item.user_id));
  const candidates=store.accounts.filter(account=>authorityIds.has(account.id)).sort((a,b)=>(a.full_name||'').localeCompare(b.full_name||''));
  async function save(event){
   event.preventDefault();
   const formElement=event.currentTarget,form=new FormData(formElement),max=String(form.get('max_budget_lkr')||'').trim();
   const payload={p_rule:null,p_name:String(form.get('name')||'').trim(),p_event_category:String(form.get('event_category')||'').trim()||null,p_min_budget_lkr:Number(form.get('min_budget_lkr')||0),p_max_budget_lkr:max===''?null:Number(max),p_recipients:selected};
   if(!selected.length){setToast({error:true,message:'Select at least one Higher Authority.'});return}
   if(await transaction(()=>call('admin_save_authority_rule',payload),'Authority routing rule saved')){setSelected([]);formElement.reset()}
  }
  return <section className="panel">
   <p>Every enabled matching rule adds its Higher Authorities to the approval set. All assigned reviewers must approve. Missing matches fail closed into a routing exception.</p>
   {store.approvalRules.map(rule=>{
    const recipientIds=store.approvalRuleRecipients.filter(item=>item.rule_id===rule.id).map(item=>item.user_id);
    const recipientNames=recipientIds.map(id=>store.accounts.find(account=>account.id===id)?.full_name||id);
    const budget=`LKR ${Number(rule.min_budget_lkr).toLocaleString()} – ${rule.max_budget_lkr===null?'no upper limit':`LKR ${Number(rule.max_budget_lkr).toLocaleString()}`}`;
    return <div className="list-item" key={rule.id}><div><strong>{rule.name}</strong><p>{rule.event_category||'All categories'} · {budget}</p><p>{recipientNames.join(', ')||'No active recipients'}</p></div><div className="buttons"><Status s={rule.enabled?'enabled':'disabled'}/><button type="button" className="btn btn-light" disabled={busy} onClick={()=>transaction(()=>call('admin_set_authority_rule_enabled',{p_rule:rule.id,p_enabled:!rule.enabled}),'Routing rule updated')}>{rule.enabled?'Disable':'Enable'}</button><button type="button" className="btn btn-danger" disabled={busy} onClick={()=>confirmAdminChange('Delete routing rule',`Delete “${rule.name}”? Existing proposal assignment snapshots will remain unchanged.`,()=>transaction(()=>call('admin_delete_authority_rule',{p_rule:rule.id}),'Routing rule deleted'))}>Delete</button></div></div>;
   })}
   {store.approvalRules.length===0&&<Empty title="No authority routing rules" subtitle="Coordinator approvals will remain in routing_exception until a matching rule is configured."/>}
   <form className="stack-form" onSubmit={save}><h3>Add routing rule</h3><label>Rule name<input name="name" minLength="3" maxLength="120" required/></label><label>Event category (blank matches all)<input name="event_category" maxLength="80"/></label><div className="form-grid"><label>Minimum budget (LKR)<input name="min_budget_lkr" type="number" min="0" step="1" defaultValue="0" required/></label><label>Maximum budget (LKR, optional)<input name="max_budget_lkr" type="number" min="0" step="1"/></label></div><fieldset className="routing-recipient-list"><legend>Required Higher Authorities</legend>{candidates.map(account=><label className="admin-checkbox" key={account.id}><input type="checkbox" checked={selected.includes(account.id)} disabled={busy} onChange={event=>setSelected(current=>event.target.checked?[...new Set([...current,account.id])]:current.filter(id=>id!==account.id))}/><span><strong>{account.full_name||'Unnamed account'}</strong><small>{account.id}</small></span></label>)}{candidates.length===0&&<Empty title="No Higher Authority accounts found"/>}</fieldset><button type="submit" className="btn btn-primary" disabled={busy||candidates.length===0}>Save routing rule</button></form>
  </section>;
 }
 function OrganizerMigrationRow({assignment}){
  const account=store.accounts.find(item=>item.id===assignment.user_id);
  const currentSeat=store.committee.find(item=>item.club_id===assignment.club_id&&item.user_id===assignment.user_id);
  const occupied=new Set(store.committee.filter(item=>item.club_id===assignment.club_id).map(item=>item.seat));
  const available=committeePositions.map((name,index)=>({name,seat:index+1})).filter(item=>!occupied.has(item.seat));
  const selectionKey=`${assignment.club_id}:${assignment.user_id}`;
  const seat=legacyMigrationSeats[selectionKey]??available[0]?.seat??1;
  const club=clubOf(assignment.club_id);
  return <div className="list-item legacy-organizer-row"><div><strong>{account?.full_name||assignment.user_id}</strong><p>{club?.name||'Club'} · {currentSeat?`Already assigned as ${currentSeat.position_name}`:'Legacy organizer assignment'}</p></div>{currentSeat?<button type="button" className="btn btn-light" disabled={busy} onClick={()=>transaction(()=>call('admin_migrate_organizer_assignment',{p_club:assignment.club_id,p_user:assignment.user_id,p_seat:currentSeat.seat}),'Legacy assignment merged into committee position')}>Merge assignment</button>:available.length>0?<div className="buttons"><label>New position<select value={seat} onChange={event=>setLegacyMigrationSeats(current=>({...current,[selectionKey]:Number(event.target.value)}))}>{available.map(item=><option key={item.seat} value={item.seat}>{item.name}</option>)}</select></label><button type="button" className="btn btn-primary" disabled={busy} onClick={()=>transaction(()=>call('admin_migrate_organizer_assignment',{p_club:assignment.club_id,p_user:assignment.user_id,p_seat:seat}),'Organizer assignment migrated')}>Assign position</button></div>:<span className="muted small">No vacant position. Assignment remains unchanged until one is available.</span>}</div>;
 }
 function LegacyOrganizerMigrations(){
  return <section className="panel"><h3>Legacy Organizer assignments</h3><p className="muted small">Assign each legacy account to an available named position manually. Existing committee positions are preserved; conflicts remain pending.</p>{store.organizers.map(assignment=><OrganizerMigrationRow key={`${assignment.club_id}-${assignment.user_id}`} assignment={assignment}/>)}{store.organizers.length===0&&<Empty title="No legacy organizer assignments"/>}</section>;
 }
 function AdminEditClub(){
  const selectedClubId=adminClubId||store.clubs[0]?.id||'';
  const club=store.clubs.find(item=>item.id===selectedClubId);
  const [logo,setLogo]=useState(null),[removeLogo,setRemoveLogo]=useState(false),[preview,setPreview]=useState('');
  useEffect(()=>{setLogo(null);setRemoveLogo(false)},[selectedClubId]);
  useEffect(()=>{if(!logo){setPreview('');return}const url=URL.createObjectURL(logo);setPreview(url);return()=>URL.revokeObjectURL(url)},[logo]);
  if(!club)return <section className="panel"><h2>Edit club</h2><Empty title="Create a club first"/></section>;
  function chooseLogo(event){
   const file=event.target.files?.[0]||null;
   if(file&&(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>5*1024*1024)){
    setLogo(null);event.target.value='';setToast({error:true,message:'Choose a PNG, JPEG, or WebP image up to 5 MB.'});return;
   }
   setLogo(file);setRemoveLogo(false);
  }
  function submit(event){
   event.preventDefault();
   const form=new FormData(event.currentTarget),name=String(form.get('name')).trim(),category=String(form.get('category')||'General'),description=String(form.get('description')||''),fee=Number(form.get('fee')),updateLogo=Boolean(logo)||removeLogo;
   confirmAdminChange('Confirm club update',`Save changes to “${club.name}”${logo?' and replace its logo':removeLogo?' and remove its logo':''}?`,async()=>{
    let uploadedPath=null,oldLogoPath=null,cleanupWarning='';
    const succeeded=await transaction(async()=>{
     if(logo){
      const extension=logo.type==='image/png'?'png':logo.type==='image/webp'?'webp':'jpg';
      uploadedPath=`${crypto.randomUUID()}.${extension}`;
      const {error}=await supabase.storage.from('club-logos').upload(uploadedPath,logo,{cacheControl:'3600',contentType:logo.type,upsert:false});
      if(error){uploadedPath=null;throw new Error(`Logo upload failed: ${error.message}`)}
     }
     try{
      oldLogoPath=await call('admin_update_club',{p_club:club.id,p_name:name,p_description:description,p_category:category,p_fee_cents:fee,p_logo_path:uploadedPath,p_update_logo:updateLogo});
     }catch(error){
      if(uploadedPath){
       const {error:cleanupError}=await supabase.storage.from('club-logos').remove([uploadedPath]);
       if(cleanupError)throw new Error(`${error.message}. Uploaded logo cleanup failed: ${cleanupError.message}`);
      }
      throw error;
     }
     if(updateLogo&&oldLogoPath&&oldLogoPath!==uploadedPath){
      const {error}=await supabase.storage.from('club-logos').remove([oldLogoPath]);
      if(error)cleanupWarning=`Club updated, but the previous logo could not be removed: ${error.message}`;
     }
    },'Club updated');
    if(succeeded&&cleanupWarning)setToast({error:true,message:cleanupWarning});
   });
  }
  return <section className="panel"><h2>Edit existing club</h2><form key={club.id} className="stack-form" onSubmit={submit}><label>Select club<select value={selectedClubId} onChange={event=>setAdminClubId(event.target.value)}>{store.clubs.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>Club name<input name="name" required minLength="2" defaultValue={club.name}/></label><label>Category<input name="category" defaultValue={club.category}/></label><label>Description<textarea name="description" defaultValue={club.description}/></label><label>Membership fee (USD cents)<input name="fee" type="number" min="0" required defaultValue={club.membership_fee_cents}/></label><label>Replace logo (PNG, JPEG, or WebP; up to 5 MB)<input type="file" accept="image/png,image/jpeg,image/webp" onChange={chooseLogo}/></label>{preview?<img className="club-logo-preview" src={preview} alt="New club logo preview"/>:club.logo_path&&!removeLogo?<img className="club-logo-preview" src={clubLogoUrl(club)} alt={`${club.name} current logo`}/>:<p className="muted small">No logo selected.</p>}{club.logo_path&&<label className="admin-checkbox"><input type="checkbox" checked={removeLogo} onChange={event=>{setRemoveLogo(event.target.checked);if(event.target.checked)setLogo(null)}}/> Remove current logo</label>}<button className="btn btn-primary">Review changes</button></form></section>;
 }
 function AdminClubAssign(){
  const selectedClubId=adminClubId||store.clubs[0]?.id||'';
  const club=store.clubs.find(item=>item.id===selectedClubId);
  if(!club)return <section className="panel"><Empty title="Create a club before assigning staff"/></section>;
  const seatUser=seat=>store.committee.find(item=>item.club_id===club.id&&item.seat===seat)?.user_id||'';
  const askAssign=(type,currentUser,user,seat)=>{
   const account=store.accounts.find(item=>item.id===user),label=type==='lecturer'?'lecturer':committeePositions[seat-1];
   confirmAdminChange('Confirm staff assignment',`Assign ${account?.full_name||'the selected account'} as ${label} for ${club.name}?`,()=>transaction(async()=>{
    if(type==='lecturer')await call('admin_assign_lecturer',{p_club:club.id,p_user:user});
    else await call('admin_assign_committee',{p_club:club.id,p_seat:seat,p_user:user});
   },'Staff assignment saved'));
  };
  const askRemove=(type,user,seat)=>{
   const account=store.accounts.find(item=>item.id===user),label=type==='lecturer'?'lecturer assignment':`${committeePositions[seat-1]} position`;
   confirmAdminChange('Confirm staff removal',`Remove ${account?.full_name||'this account'} from the ${label} assignment for ${club.name}?`,()=>transaction(()=>{
    if(type==='lecturer')return call('admin_clear_club_lecturer',{p_club:club.id});
    return call('admin_remove_committee_seat',{p_club:club.id,p_seat:seat});
   },'Staff assignment removed'));
  };
  return <section className="panel"><div className="staff-club-picker"><label>Selected club<select value={selectedClubId} onChange={event=>setAdminClubId(event.target.value)}>{store.clubs.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><p>Committee assignments use the five fixed positions. Use the migration queue below for legacy organizer assignments.</p></div><div className="staff-assignment-list"><StaffAssignmentRow label="Lecturer coordinator" userId={club.lecturer_id} accounts={store.accounts} onAssign={user=>askAssign('lecturer',club.lecturer_id,user)} onRemove={()=>askRemove('lecturer',club.lecturer_id)}/>{committeePositions.map((label,index)=>{const seat=index+1;return <StaffAssignmentRow key={`seat-${seat}`} label={label} userId={seatUser(seat)} accounts={store.accounts} onAssign={user=>askAssign('committee',seatUser(seat),user,seat)} onRemove={()=>askRemove('committee',seatUser(seat),seat)}/>})}</div></section>;
 }

 let content;
 switch(allowed){case'explore':content=explore();break;case'calendar':content=calendarPage();break;case'events':content=myEvents();break;case'clubs':content=clubsPage();break;case'memberships':content=myMemberships();break;case'payments':content=payments();break;case'badges':content=badges();break;case'permissions':content=permissionsPage();break;case'notifications':content=notificationsPage();break;case'profile':content=profilePage();break;case'proposals':content=proposalPage();break;case'audit':content=auditPage();break;case'members':content=membersPage();break;case'registrations':content=registrationsPage();break;case'finance':content=financePage();break;case'reviews':content=reviewsPage();break;case'admin':content=adminPage();break;case'attendance':content=attendancePage();break;default:content=dashboard()}
 if(demoMode)content=<><div className="demo-preview-banner"><strong>Demo preview</strong><span>Changes are disabled and nothing is sent to Supabase.</span><button type="button" className="btn btn-light" onClick={exitDemoPreview}>Exit preview</button></div>{content}</>;
 const titles={dashboard:'Dashboard',explore:'Explore events',calendar:'Campus calendar',events:'My events',clubs:'University clubs',memberships:'My memberships',payments:'My payments',badges:role==='committee'?'Badge authorization':'Digital badges',permissions:'My role & permissions',notifications:'Notifications',profile:'My profile',proposals:'Event proposals',audit:'Audit history',members:'Membership requests',registrations:'Event registrations',finance:'Finance',reviews:'Approval inbox',admin:'Administration',attendance:'Attendance check-in'};

 return <div className={`shell ${busy?'busy':''}`}>
  <aside className="sidebar">
   <a className="brand" href="#/dashboard"><span className="brand-mark">✦</span><span>UniEvents<small>YOUR CAMPUS, CONNECTED</small></span></a>
   <nav>{roleNav.map(([id,label])=><a key={id} className={`nav-item ${id===allowed?'on':''}`} href={`#/${id}`}>{label}</a>)}</nav>
   <button className="nav-item signout" onClick={()=>action('logout')}>Sign out</button>
  </aside>
  <div className="workspace">
   <header className="topbar">
    <div className="crumb">UniEvents / {titles[allowed]}</div>
    <div className="topbar-right">
     {role==='committee'&&<div className="club-context-switcher">
      <span>Active club</span>
      {assignedClubIds.length>1
       ?<select aria-label="Active club" value={activeClubId} onChange={event=>{setClubContextId(event.target.value);setModal(null)}}>{assignedClubIds.map(clubId=><option key={clubId} value={clubId}>{clubOf(clubId)?.name||'Club'}</option>)}</select>
       :<strong>{clubOf(activeClubId)?.name||'No club assigned'}</strong>}
      {activeClubPositions.length>0&&<small>{activeClubPositions.join(', ')}</small>}
     </div>}
     <label className={`role-switcher ${roleSwitching?'is-loading':''}`}><span className="sr-only">Active role</span><select id="role-switch" value={role} disabled={roleSwitching} aria-busy={roleSwitching} onChange={event=>switchRole(event.target.value)}>{store.roles.map(r=><option key={r} value={r}>{r}</option>)}</select>{roleSwitching&&<><span className="button-spinner" aria-hidden="true"/><span className="sr-only" role="status">Switching role…</span></>}</label>
     <span className="avatar">{store.profile?.full_name?.[0]||'U'}</span>
    </div>
   </header>
   <main key={allowed} className="main route-transition">{content}</main>
  </div>
  {busy&&<div className="global-loading" role="status" aria-live="polite"><span/>Saving your changes…</div>}
  {toast&&<div className={`toast ${toast.error?'toast-error':''}`}>{toast.message}</div>}
 {modal?.type==='event'&&<EventModal id={modal.id} onClose={()=>setModal(null)} action={action}/>}
 {modal?.type==='cancel-event'&&<Modal onClose={()=>setModal(null)}><span className="eyebrow teal">EVENT CANCELLATION</span><h2>Cancel this event?</h2><p>Registrations will be cancelled and eligible paid transactions will enter the refund workflow. Refund approval is not proof of gateway completion.</p><form className="stack-form" onSubmit={event=>{event.preventDefault();const form=new FormData(event.currentTarget);transaction(()=>call('cancel_event',{p_proposal:modal.proposalId,p_reason:String(form.get('reason')||'').trim()}),'Event cancelled')}}><label>Reason<textarea name="reason" minLength="3" maxLength="2000" required/></label><div className="buttons"><button type="button" className="btn btn-light" onClick={()=>setModal(null)} disabled={busy}>Keep event</button><button type="submit" className="btn btn-danger" disabled={busy}>{busy?'Cancelling…':'Confirm cancellation'}</button></div></form></Modal>}
 {modal?.type==='external-registration-decision'&&<Modal onClose={()=>setModal(null)}><span className="eyebrow teal">REGISTRATION VERIFICATION</span><h2>{modal.verified?'Verify external registration':'Reject external registration'}</h2><p>Record the evidence checked and decision reason. This does not mark attendance.</p><form className="stack-form" onSubmit={event=>{event.preventDefault();const form=new FormData(event.currentTarget);transaction(()=>call('verify_external_registration',{p_registration:modal.registration.id,p_verified:modal.verified,p_reason:String(form.get('reason')||'').trim()}),modal.verified?'External registration verified':'External registration rejected')}}><label>Verification notes<textarea name="reason" minLength="3" maxLength="2000" required/></label><div className="buttons"><button type="button" className="btn btn-light" onClick={()=>setModal(null)} disabled={busy}>Cancel</button><button type="submit" className={`btn ${modal.verified?'btn-primary':'btn-danger'}`} disabled={busy}>{busy?'Saving…':modal.verified?'Confirm verification':'Record not verified'}</button></div></form></Modal>}
 {modal?.type==='refund-decision'&&<Modal onClose={()=>setModal(null)}><span className="eyebrow teal">REFUND DECISION</span><h2>{modal.approve?'Approve refund request':'Reject refund request'}</h2><p>Approval records an officer decision only. No money is marked returned until the payment provider confirms it.</p><form className="stack-form" onSubmit={event=>{event.preventDefault();const form=new FormData(event.currentTarget);transaction(()=>call('decide_refund_request',{p_refund:modal.refund.id,p_approve:modal.approve,p_reason:String(form.get('reason')||'').trim()}),modal.approve?'Refund approved':'Refund rejected')}}><label>Decision reason<textarea name="reason" minLength="3" maxLength="2000" required/></label><div className="buttons"><button type="button" className="btn btn-light" onClick={()=>setModal(null)} disabled={busy}>Cancel</button><button type="submit" className={`btn ${modal.approve?'btn-primary':'btn-danger'}`} disabled={busy}>{busy?'Saving…':modal.approve?'Approve refund':'Reject refund'}</button></div></form></Modal>}
 {modal?.type==='admin-confirm'&&<Modal onClose={()=>setModal(null)}><span className="eyebrow teal">ADMINISTRATOR CONFIRMATION</span><h2>{modal.title}</h2><p>{modal.summary}</p><p className="muted small">This will immediately update the Supabase project.</p><div className="buttons"><button type="button" className="btn btn-light" onClick={()=>setModal(null)} disabled={busy}>Cancel</button><button type="button" className="btn btn-primary" onClick={modal.onConfirm} disabled={busy}>{busy?'Applying…':'Confirm and apply'}</button></div></Modal>}
 {modal?.type==='badge-decision'&&<Modal onClose={()=>setModal(null)}><span className="eyebrow teal">BADGE AUTHORIZATION</span><h2>{modal.approve?'Approve badge':'Reject badge candidate'}</h2><p>{store.badgeProfiles.find(profile=>profile.id===modal.candidate.user_id)?.full_name||'Student'} · {vOf(store.proposals.find(proposal=>proposal.id===modal.candidate.proposal_id))?.title||'Campus event'}</p><form className="stack-form" onSubmit={event=>{event.preventDefault();const form=new FormData(event.currentTarget);transaction(()=>call('decide_badge_candidate',{p_candidate:modal.candidate.id,p_approve:modal.approve,p_reason:String(form.get('reason')||'').trim()}),modal.approve?'Badge authorized':'Badge candidate rejected')}}><label>Decision reason<textarea name="reason" minLength="3" maxLength="2000" required/></label><div className="buttons"><button type="button" className="btn btn-light" onClick={()=>setModal(null)} disabled={busy}>Cancel</button><button type="submit" className={`btn ${modal.approve?'btn-primary':'btn-danger'}`} disabled={busy}>{busy?'Saving…':modal.approve?'Authorize badge':'Reject candidate'}</button></div></form></Modal>}
 {modal?.type==='routing-retry'&&<Modal onClose={()=>setModal(null)}><span className="eyebrow teal">AUTHORITY ROUTING</span><h2>Retry authority routing?</h2><p>Route this proposal using the current Admin-configured recipients.</p><div className="buttons"><button className="btn btn-light" onClick={()=>setModal(null)}>Cancel</button><button className="btn btn-primary" onClick={()=>transaction(()=>call('admin_retry_authority_routing',{p_proposal:modal.proposalId}),'Authority reviews routed')}>Retry routing</button></div></Modal>}
 {modal?.type==='proposal'&&<ProposalModal id={modal.id} clubIds={scopedClubIds} onClose={()=>setModal(null)} transaction={transaction} onRetryRouting={id=>setModal({type:'routing-retry',proposalId:id})} onCancelEvent={proposalId=>setModal({type:'cancel-event',proposalId})} onRevise={proposal=>setModal({type:'proposal-form',proposal})}/>}
 {modal?.type==='proposal-form'&&<ProposalFormModal proposal={modal.proposal} clubIds={scopedClubIds} onClose={()=>setModal(null)} transaction={transaction}/>}
 </div>;
}

function EventModal({id,onClose,action}){
 const e=store.events.find(x=>x.id===id);if(!e)return null;const v=e.version,r=store.registrations.find(x=>x.proposal_id===id&&x.user_id===store.user.id),cancellation=store.eventCancellations.find(item=>item.proposal_id===id);
 const formSchema=Array.isArray(v.registration_form_schema)?v.registration_form_schema:[];
 const fee=v.fee_lkr>0?`LKR ${Number(v.fee_lkr).toLocaleString()}`:money(v.fee_cents);
 function submitInternal(event){
  event.preventDefault();
  const form=new FormData(event.currentTarget),answers={};
  for(const field of formSchema){
   if(field.type==='checkbox'){answers[field.key]=form.has(field.key);continue}
   const raw=String(form.get(field.key)||'').trim();
   if(raw==='')continue;
   answers[field.key]=field.type==='number'?Number(raw):raw;
  }
  action('register',id,{answers});
 }
 return <Modal onClose={onClose}><span className="eyebrow teal">{clubOf(e.club_id)?.name}</span><h2>{v.title}</h2><p>{v.description}</p><div className="details-grid"><p><strong>Date</strong><br/>{date(v.starts_at)}</p><p><strong>Venue</strong><br/>{v.venue}</p><p><strong>Fee</strong><br/>{fee}</p><p><strong>Category</strong><br/>{v.event_category||'General'}</p></div>
  {v.purpose&&<p>{v.purpose}</p>}{e.event_lifecycle==='cancelled'&&<div className="notice danger">This event has been cancelled.{cancellation&&<> Reason: {cancellation.reason}</>}</div>}
  <div className="modal-actions">{r?<div><Status s={r.status}/>{r.verification_status==='pending'&&<p className="muted small">External registration is awaiting committee verification.</p>}{r.verification_status==='not_verified'&&<p className="notice danger">{r.verification_reason||'External registration was not verified.'}</p>}{r.confirmation_code&&<p className="muted small">Confirmation: {r.confirmation_code}</p>}</div>
   :e.event_lifecycle==='cancelled'?null
   :v.registration_method==='none'?<span className="muted small">Registration is not offered for this event.</span>
   :Number(v.fee_lkr)>0||Number(v.fee_cents)>0?<span className="muted small">Paid registration is unavailable until a payment provider is configured.</span>
   :v.registration_method==='external'?<div className="stack-form">{!v.registration_required&&<p className="muted small">Registration is optional.</p>}<a className="btn btn-light" href={v.external_registration_url} target="_blank" rel="noreferrer">Open external registration form</a><form className="stack-form" onSubmit={event=>{event.preventDefault();const form=new FormData(event.currentTarget);action('external-register',id,{reference:String(form.get('external_reference')||'').trim()})}}><label>External submission reference or confirmation<textarea name="external_reference" maxLength="500" required/></label><button className="btn btn-primary">Submit for verification</button></form></div>
   :<form className="stack-form" onSubmit={submitInternal}>{!v.registration_required&&<p className="muted small">Registration is optional.</p>}{formSchema.map(field=><label key={field.key}>{field.label}{field.type==='select'?<select name={field.key} required={Boolean(field.required)} defaultValue=""><option value="">Select…</option>{(field.options||[]).map(option=><option key={option} value={option}>{option}</option>)}</select>:field.type==='checkbox'?<input name={field.key} type="checkbox" required={Boolean(field.required)}/>:<input name={field.key} type={field.type==='email'?'email':field.type==='number'?'number':'text'} required={Boolean(field.required)}/>}</label>)}<button className="btn btn-primary">Submit registration</button></form>}
  </div></Modal>;
}
function ProposalModal({id,clubIds,onClose,transaction,onRevise,onRetryRouting,onCancelEvent}){
 const p=store.proposals.find(x=>x.id===id),[viewVersion,setViewVersion]=useState(null);
 const [documentBusy,setDocumentBusy]=useState(false),[documentError,setDocumentError]=useState(''),[documentRefresh,setDocumentRefresh]=useState(0);
 useEffect(()=>setViewVersion(null),[id]);
 if(!p)return null;
 const versions=store.versions.filter(item=>item.proposal_id===id).sort((a,b)=>a.version-b.version);
 const selectedVersion=viewVersion??p.current_version;
 const v=versions.find(item=>item.version===selectedVersion)||vOf(p),previous=versions.find(item=>item.version===selectedVersion-1);
 const mine=clubIds.includes(p.club_id),assigned=store.reviewers.filter(r=>r.proposal_id===id&&r.version===p.current_version),decisions=store.decisions.filter(d=>d.proposal_id===id),currentDecisions=decisions.filter(d=>d.version===p.current_version),myDecision=currentDecisions.some(d=>d.reviewer_id===store.user.id),viewingCurrent=selectedVersion===p.current_version;
 const canReview=viewingCurrent&&((store.role==='lecturer'&&p.status==='lecturer_pending')||(store.role==='authority'&&p.status==='authority_pending'&&assigned.some(r=>r.user_id===store.user.id)&&!myDecision));
 const canComment=viewingCurrent&&(store.role==='admin'||store.role==='lecturer'||store.role==='authority'||hasPermission(p.club_id,'proposal.comment'));
 const canSubmit=hasPermission(p.club_id,'event.proposal.submit');
 const canUploadDocument=viewingCurrent&&(mine||store.role==='admin')&&(p.status==='draft'||p.status==='changes_requested')
  &&(hasPermission(p.club_id,'event.create')||canSubmit);
 const documents=store.proposalDocuments.filter(document=>document.proposal_id===id&&document.version===selectedVersion);
 async function uploadDocument(event){
  const file=event.target.files?.[0];
  if(!file)return;
  setDocumentError('');
  const allowedTypes=['application/pdf','image/jpeg','image/png','image/webp','application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
  if(!allowedTypes.includes(file.type)||file.size<1||file.size>10*1024*1024){
   event.target.value='';
   setDocumentError('Choose a PDF, DOCX, JPEG, PNG, or WebP file up to 10 MB.');
   return;
  }
  const safeName=file.name.replace(/[^a-zA-Z0-9._-]/g,'_').slice(-180)||'document';
  const objectPath=`${id}/${selectedVersion}/${store.user.id}/${crypto.randomUUID()}-${safeName}`;
  setDocumentBusy(true);
  let uploaded=false;
  try{
   const {error:uploadError}=await supabase.storage.from('proposal-documents').upload(objectPath,file,{cacheControl:'3600',contentType:file.type,upsert:false});
   if(uploadError)throw new Error(`Document upload failed: ${uploadError.message}`);
   uploaded=true;
   await call('add_proposal_document',{p_proposal:id,p_version:selectedVersion,p_object_path:objectPath,p_file_name:file.name,p_mime_type:file.type});
   await refresh({strict:true});
   setDocumentRefresh(value=>value+1);
   event.target.value='';
  }catch(error){
   if(uploaded){
    try{
     const {error:cleanupError}=await supabase.storage.from('proposal-documents').remove([objectPath]);
     if(cleanupError)throw cleanupError;
     setDocumentError(error.message||'Could not attach the document.');
    }catch(cleanupError){setDocumentError(`${error.message}. Uploaded file cleanup failed: ${cleanupError.message}`)}
   }else setDocumentError(error.message||'Could not attach the document.');
  }finally{setDocumentBusy(false)}
 }
 async function openDocument(file){
  setDocumentError('');
  try{
   const {data,error}=await supabase.storage.from('proposal-documents').createSignedUrl(file.object_path,60);
   if(error)throw new Error(error.message);
   if(!window.open(data.signedUrl,'_blank','noopener,noreferrer'))throw new Error('Allow pop-ups to open the secure document link.');
  }catch(error){setDocumentError(error.message||'Could not open this document.')}
 }
 const lecturer=store.clubs.find(club=>club.id===p.club_id)?.lecturer_id;
 const actorName=userId=>store.badgeProfiles.find(profile=>profile.id===userId)?.full_name||`User ${String(userId||'system').slice(0,8)}`;
 const activity=[
  ...versions.map(item=>({id:`version-${item.version}`,type:'version',created_at:item.created_at,version:item.version})),
  ...store.comments.filter(item=>item.proposal_id===id).map(item=>({id:item.id,type:'comment',created_at:item.created_at,version:item.version,actor:item.author_id,body:item.body})),
  ...decisions.map(item=>({id:item.id,type:'decision',created_at:item.created_at,version:item.version,actor:item.reviewer_id,stage:item.stage,decision:item.decision,body:item.comment}))
 ].sort((a,b)=>new Date(a.created_at||0)-new Date(b.created_at||0));
 const fields=[
  ['title','Title',value=>value],
  ['description','Description',value=>value],
  ['starts_at','Starts',value=>value?`${date(value)} ${time(value)}`:'—'],
  ['ends_at','Ends',value=>value?`${date(value)} ${time(value)}`:'—'],
  ['venue','Venue',value=>value],
  ['capacity','Capacity',value=>String(value)],
  ['event_category','Category',value=>value||'General'],
  ['purpose','Purpose',value=>value||'—'],
  ['eligibility_policy','Eligibility',value=>value?.replaceAll('_',' ')||'all students'],
  ['registration_method','Registration method',value=>value||'internal'],
  ['registration_required','Registration required',value=>value?'Yes':'No'],
  ['registration_deadline','Registration deadline',value=>value?`${date(value)} ${time(value)}`:'No deadline'],
  ['external_registration_url','External registration URL',value=>value||'—'],
  ['registration_form_schema','Registration form',value=>JSON.stringify(value||[])],
  ['fee_lkr','Participation fee (LKR)',value=>`LKR ${Number(value||0).toLocaleString()}`],
  ['budget_lkr','Estimated budget (LKR)',value=>`LKR ${Number(value||0).toLocaleString()}`],
  ['change_reason','Revision reason',value=>value||'—'],
 ];
 const differences=previous&&v?fields.filter(([key])=>previous[key]!==v[key]):[];
 const currentDecisionFor=(stage,userId)=>currentDecisions.find(item=>item.stage===stage&&(!userId||item.reviewer_id===userId));
 const stageStatus=(stage,userId)=>currentDecisionFor(stage,userId)?.decision||'pending';
 return <Modal big onClose={onClose}>
  <span className="eyebrow teal">{clubOf(p.club_id)?.name} · VERSION {selectedVersion}{viewingCurrent?' · CURRENT':''}</span>
  <h2>{v?.title}</h2><Status s={p.status}/><p className="modal-description">{v?.description}</p>
  <section className="panel"><h3>Version history</h3><label>Viewing version<select value={selectedVersion} onChange={event=>setViewVersion(Number(event.target.value))}>{versions.map(item=><option key={item.version} value={item.version}>Version {item.version}{item.version===p.current_version?' (current)':''} · {date(item.created_at)}</option>)}</select></label>{!previous&&selectedVersion===1&&<p className="muted small">This is the first saved version.</p>}{previous&&v&&<><h4>Changes from Version {previous.version}</h4>{differences.length===0?<p className="muted small">No field changes.</p>:<div className="table-card"><table><thead><tr><th>FIELD</th><th>PREVIOUS</th><th>THIS VERSION</th></tr></thead><tbody>{differences.map(([key,label,format])=><tr key={key}><th>{label}</th><td>{format(previous[key])}</td><td>{format(v[key])}</td></tr>)}</tbody></table></div>}</>}</section>
  <section className="panel" key={`documents-${documentRefresh}`}><h3>Version documents</h3><p className="muted small">Restricted files are available only to authorized proposal participants and the published version.</p>{documents.map(file=><div className="list-item" key={file.id}><div><strong>{file.file_name}</strong><p>{file.mime_type} · {(file.file_size_bytes/1024/1024).toFixed(2)} MB · {date(file.created_at)}</p></div><button type="button" className="btn btn-light" onClick={()=>openDocument(file)}>Open secure link</button></div>)}{documents.length===0&&<p className="muted small">No files attached to this version.</p>}{canUploadDocument&&<label className="stack-form">Attach proposal document<input type="file" accept=".pdf,.docx,image/jpeg,image/png,image/webp" disabled={documentBusy} onChange={uploadDocument}/>{documentBusy&&<span className="muted small">Uploading securely…</span>}</label>}{documentError&&<div className="notice danger" role="alert">{documentError}</div>}</section>
  <section className="panel"><h3>Approval progress · Version {p.current_version}</h3><div className="list-item"><div><strong>Lecturer Coordinator</strong><p>{lecturer?actorName(lecturer):'No Coordinator assigned'}</p></div><Status s={stageStatus('lecturer',lecturer)}/></div>{assigned.map(reviewer=><div className="list-item" key={reviewer.user_id}><div><strong>Higher Authority</strong><p>{actorName(reviewer.user_id)}</p></div><Status s={stageStatus('authority',reviewer.user_id)}/></div>)}{assigned[0]?.rule_snapshot?.length>0&&<p className="muted small">Routing snapshot: {assigned[0].rule_snapshot.map(rule=>`${rule.name} (${rule.category||'all categories'}, LKR ${Number(rule.min_budget_lkr).toLocaleString()}–${rule.max_budget_lkr===null?'unbounded':Number(rule.max_budget_lkr).toLocaleString()})`).join('; ')}</p>}{p.status==='routing_exception'&&<div className="notice danger">Authority routing needs Admin attention. This proposal is not fully approved.</div>}{p.status==='approved_unpublished'&&<div className="notice">All required reviews are complete. Publication is a separate action.</div>}</section>
  <h3>Shared proposal activity</h3><div className="decision-list">{activity.map(item=><div className="decision" key={item.id}><span>{item.type==='version'?`Version ${item.version} snapshot`:item.type==='comment'?`Comment · ${actorName(item.actor)}`:`${item.stage} decision · ${actorName(item.actor)}`} · V{item.version} · {item.created_at?new Date(item.created_at).toLocaleString():'Time unavailable'}{item.type==='decision'&&<> · <Status s={item.decision}/></>}</span>{(item.type==='comment'||item.type==='decision')&&item.body&&<small>{item.body}</small>}</div>)}{activity.length===0&&<Empty title="No activity recorded yet"/>}</div>
  {canComment&&<form className="stack-form" onSubmit={event=>{event.preventDefault();const form=new FormData(event.currentTarget);transaction(()=>call('add_proposal_comment',{p_proposal:id,p_body:String(form.get('body')).trim()}),'Comment added')}}><label>New comment for current version<textarea name="body" maxLength="3000" required/></label><button className="btn btn-light">Add comment</button></form>}{!viewingCurrent&&<p className="muted small">Historical versions are read-only. Switch to the current version to comment or take an action.</p>}
  <div className="modal-actions">{viewingCurrent&&mine&&p.status==='draft'&&canSubmit&&<button className="btn btn-primary" onClick={()=>transaction(()=>call('submit_proposal',{p_proposal:id}),'Proposal submitted')}>Submit to lecturer</button>} {viewingCurrent&&mine&&p.status==='changes_requested'&&canSubmit&&<button className="btn btn-primary" onClick={()=>onRevise(p)}>Revise &amp; resubmit</button>} {viewingCurrent&&mine&&p.status==='approved_unpublished'&&hasPermission(p.club_id,'event.publish')&&<button className="btn btn-primary" onClick={()=>transaction(()=>call('publish_proposal',{p_proposal:id}),'Event published')}>Publish event</button>} {viewingCurrent&&mine&&p.status==='published'&&p.event_lifecycle!=='cancelled'&&hasPermission(p.club_id,'event.cancel')&&<button className="btn btn-danger" onClick={()=>onCancelEvent?.(p.id)}>Cancel event</button>} {store.role==='admin'&&p.status==='routing_exception'&&<button className="btn btn-primary" onClick={()=>onRetryRouting?.(id)}>Retry authority routing</button>}{canReview&&<DecisionForm id={id} role={store.role} transaction={transaction}/>}</div>
 </Modal>;
}
function DecisionForm({id,role,transaction}){
 const [error,setError]=useState('');
 return <form className="stack-form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget),decision=e.nativeEvent.submitter?.value,comment=String(f.get('comment')||'').trim();if(decision!=='approved'&&comment.length<3){setError('Provide a reason of at least 3 characters for this decision.');return}setError('');transaction(()=>call(role==='lecturer'?'lecturer_decide':'authority_decide',{p_proposal:id,p_decision:decision,p_comment:comment}),'Review decision recorded')}}><label>Review comment<textarea name="comment" maxLength="2000"/></label>{error&&<div className="notice danger" role="alert">{error}</div>}<div className="buttons"><button name="decision" value="approved" className="btn btn-primary">Approve</button><button name="decision" value="changes_requested" className="btn btn-light">Request changes</button><button name="decision" value="rejected" className="btn btn-danger">Reject</button></div></form>;
}

function ProposalFormModal({proposal,clubIds,onClose,transaction}) {
 const v=vOf(proposal);
 async function submit(event) {
  event.preventDefault();
  const form=new FormData(event.currentTarget);
  await transaction(
   ()=>{
    const start=new Date(String(form.get('starts_at')));
    const end=new Date(String(form.get('ends_at')));
    if (!(start<end)) throw new Error('End time must be after start time');
    let formSchema;
    try { formSchema=JSON.parse(String(form.get('registration_form_schema')||'[]')); }
    catch { throw new Error('Registration form fields must be valid JSON.'); }
    if(!Array.isArray(formSchema))throw new Error('Registration form fields must be a JSON array.');
    const deadlineValue=String(form.get('registration_deadline')||'');
    const registrationMethod=String(form.get('registration_method'));
    const payload={
     p_title:String(form.get('title')).trim(),
     p_description:String(form.get('description')).trim(),
     p_starts_at:start.toISOString(),
     p_ends_at:end.toISOString(),
     p_venue:String(form.get('venue')).trim(),
     p_capacity:Number(form.get('capacity')),
     p_event_category:String(form.get('event_category')).trim(),
     p_purpose:String(form.get('purpose')).trim(),
     p_eligibility_policy:String(form.get('eligibility_policy')),
     p_registration_required:registrationMethod==='none'?false:form.has('registration_required'),
     p_registration_method:registrationMethod,
     p_registration_deadline:deadlineValue?new Date(deadlineValue).toISOString():null,
     p_external_registration_url:registrationMethod==='external'?String(form.get('external_registration_url')||'').trim()||null:null,
     p_form_schema:registrationMethod==='internal'?formSchema:[],
     p_fee_lkr:Number(form.get('fee_lkr')||0),
     p_budget_lkr:Number(form.get('budget_lkr')||0),
    };
    if (!payload.p_title||payload.p_capacity<1||payload.p_fee_lkr<0||payload.p_budget_lkr<0) throw new Error('Invalid proposal values');
    return proposal
     ?call('resubmit_proposal_with_registration',{p_proposal:proposal.id,...payload,p_change_reason:String(form.get('change_reason')||'').trim()})
     :call('create_proposal_with_registration',{p_club:String(form.get('club_id')),...payload});
   },
   proposal?'Corrected version submitted':'Proposal draft created',
  );
 }
 const clubs=store.clubs.filter(c=>clubIds.includes(c.id));
 return <Modal big onClose={onClose}>
  <span className="eyebrow teal">CLUB COMMITTEE</span>
  <h2>{proposal?'Revise proposal':'Create event proposal'}</h2>
  <form className="stack-form" onSubmit={submit}>
   <label>Club<select name="club_id" required disabled={Boolean(proposal)} defaultValue={proposal?.club_id||clubs[0]?.id}>{clubs.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
   <label>Event title<input name="title" required minLength="4" defaultValue={v?.title||''}/></label>
   <label>Description<textarea name="description" required defaultValue={v?.description||''}/></label>
   <label>Starts at<input name="starts_at" type="datetime-local" required defaultValue={v?new Date(v.starts_at).toISOString().slice(0,16):''}/></label>
   <label>Ends at<input name="ends_at" type="datetime-local" required defaultValue={v?new Date(v.ends_at).toISOString().slice(0,16):''}/></label>
   <label>Venue<input name="venue" required defaultValue={v?.venue||''}/></label>
   <label>Capacity<input name="capacity" type="number" min="1" max="20000" required defaultValue={v?.capacity||80}/></label>
   <label>Category<input name="event_category" maxLength="80" required defaultValue={v?.event_category||'General'}/></label>
   <label>Purpose<textarea name="purpose" maxLength="3000" defaultValue={v?.purpose||''}/></label>
   <label>Eligibility<select name="eligibility_policy" defaultValue={v?.eligibility_policy||'all_students'}><option value="all_students">All eligible students</option><option value="club_members">Active club members only</option></select></label>
   <label>Registration method<select name="registration_method" defaultValue={v?.registration_method||'internal'}><option value="internal">UniEvents form</option><option value="external">External form</option><option value="none">No registration</option></select></label>
   <label className="inline-check"><input name="registration_required" type="checkbox" defaultChecked={v?.registration_required??true}/>Registration is required</label>
   <label>Registration deadline<input name="registration_deadline" type="datetime-local" defaultValue={v?.registration_deadline?new Date(v.registration_deadline).toISOString().slice(0,16):''}/></label>
   <label>External registration HTTPS URL<input name="external_registration_url" type="url" defaultValue={v?.external_registration_url||''}/></label>
   <label>Internal form fields (JSON)<textarea name="registration_form_schema" rows="5" defaultValue={JSON.stringify(v?.registration_form_schema||[],null,2)}/><small>Supported types: text, email, number, select, checkbox. Example: <code>{'[{"key":"diet","label":"Dietary needs","type":"text","required":false}]'}</code></small></label>
   <label>Participation fee (LKR)<input name="fee_lkr" type="number" min="0" step="1" required defaultValue={v?.fee_lkr||0}/></label>
   {v?.fee_cents>0&&<div className="notice">This version has a legacy USD test fee. Enter the intended LKR fee before resubmitting; paid checkout stays disabled.</div>}
   <label>Estimated budget (LKR)<input name="budget_lkr" type="number" min="0" step="1" required defaultValue={v?.budget_lkr||0}/></label>
   {proposal&&<label>Reason for this revision<textarea name="change_reason" minLength="3" maxLength="2000" required/></label>}
   <button className="btn btn-primary">{proposal?'Resubmit corrected version':'Create draft'}</button>
  </form>
 </Modal>;
}
