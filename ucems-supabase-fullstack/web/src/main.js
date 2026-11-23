import {supabase,configured,assertReady,call} from './client.js';
import {store,loadSession,refresh,checkout} from './data.js';
import {renderPage,renderAuth,proposalModal,eventModal,formModal,allowed,esc,icon} from './ui.js';
import QRCode from 'qrcode';
import './style.css';
const app=document.getElementById('app');
let overlay='';let busy=false;
const page=()=>location.hash.match(/^#\/([a-z-]+)/)?.[1]||'dashboard';
function toast(message,isError=false){let t=document.querySelector('.toast');if(t)t.remove();t=document.createElement('div');t.className='toast '+(isError?'toast-error':'');t.textContent=message;document.body.appendChild(t);setTimeout(()=>t.remove(),5200)}
function render(){if(!store.user){app.innerHTML=renderAuth(configured);return;}const destination=allowed(page())?page():'dashboard';app.innerHTML=renderPage(destination,overlay);document.title=`${destination.charAt(0).toUpperCase()+destination.slice(1)} · UniEvents`;}
function wait(on){busy=on;document.body.classList.toggle('busy',on)}
async function transaction(fn,message){if(busy)return;wait(true);try{await fn();await refresh();overlay='';render();if(message)toast(message)}catch(e){console.error(e);toast(e?.message||'Action failed',true)}finally{wait(false)}}
async function bootstrap(){if(!configured){render();return;}try{await loadSession();if(store.user)await refresh();render()}catch(e){console.error(e);toast(e.message,true);render()}}
async function dataFromProposal(form){const f=new FormData(form);const start=new Date(String(f.get('starts_at'))),end=new Date(String(f.get('ends_at')));if(!(start<end))throw new Error('End time must be after start time');const fee=Number(f.get('fee_cents'));const capacity=Number(f.get('capacity'));if(!Number.isInteger(fee)||fee<0||!Number.isInteger(capacity)||capacity<1)throw Error('Invalid capacity or fee');return {p_title:String(f.get('title')).trim(),p_description:String(f.get('description')).trim(),p_starts_at:start.toISOString(),p_ends_at:end.toISOString(),p_venue:String(f.get('venue')).trim(),p_capacity:capacity,p_fee_cents:fee}}
async function onSubmit(event){const form=event.target;if(!form?.id)return;event.preventDefault();switch(form.id){
 case 'login-form':return transaction(async()=>{assertReady();const f=new FormData(form);const {error}=await supabase.auth.signInWithPassword({email:String(f.get('email')),password:String(f.get('password'))});if(error)throw error;await loadSession();location.hash='#/dashboard'},'Signed in successfully');
 case 'signup-form':return transaction(async()=>{assertReady();const f=new FormData(form);const {data,error}=await supabase.auth.signUp({email:String(f.get('email')),password:String(f.get('password')),options:{data:{full_name:String(f.get('full_name'))}}});if(error)throw error;if(data.session){await loadSession();location.hash='#/dashboard'}else toast('Check your email to confirm your account. Then sign in.')},'Account request submitted');
 case 'proposal-form':return transaction(async()=>{const payload=await dataFromProposal(form);const id=form.dataset.id;if(id)await call('resubmit_proposal',{p_proposal:id,...payload});else await call('create_proposal',{p_club:new FormData(form).get('club_id'),...payload})},form.dataset.id?'Corrected version sent back to lecturer':'Proposal draft created');
 case 'comment-form':return transaction(async()=>{const f=new FormData(form);await call('add_proposal_comment',{p_proposal:form.dataset.id,p_body:String(f.get('body')).trim()})},'Comment added to current proposal version');
 case 'decision-form':return transaction(async()=>{const formData=new FormData(form);const decision=event.submitter?.value;if(!['approved','changes_requested','rejected'].includes(decision))throw Error('Unknown decision');if(decision==='changes_requested'&&!String(formData.get('comment')).trim())throw Error('Explain the requested corrections');const target=store.role==='lecturer'?'lecturer_decide':'authority_decide';await call(target,{p_proposal:form.dataset.id,p_decision:decision,p_comment:String(formData.get('comment')||'')})},'Review decision recorded on current version');
 case 'create-club':return transaction(async()=>{const f=new FormData(form);await call('admin_create_club',{p_name:String(f.get('name')),p_description:String(f.get('description')||''),p_category:String(f.get('category')||'General'),p_fee_cents:Number(f.get('fee'))})},'Club created');
 case 'assign-role':return transaction(async()=>{const f=new FormData(form);await call('admin_assign_role',{p_user:f.get('user'),p_role:f.get('role')})},'Role assigned');
 case 'club-assign':return transaction(async()=>{const f=new FormData(form),type=f.get('type'),p_club=f.get('club'),p_user=f.get('user');if(type==='lecturer')await call('admin_assign_lecturer',{p_club,p_user});else if(type==='organizer')await call('admin_assign_organizer',{p_club,p_user});else await call('admin_assign_committee',{p_club,p_seat:Number(type),p_user})},'Club assignment saved');
 case 'reviewer-assign':return transaction(async()=>{const f=new FormData(form);await call('admin_assign_reviewer',{p_proposal:f.get('proposal'),p_user:f.get('user')})},'Reviewer assigned');
 case 'scan-form':return transaction(async()=>{const f=new FormData(form);const result=await call('scan_attendance_token',{p_token:String(f.get('token')).trim()});if(!result.ok)throw Error('Check-in failed')},'Attendance verified. Digital badge issued.');
 }}
async function onClick(event){const el=event.target.closest('[data-act]');if(!el)return;const act=el.dataset.act,id=el.dataset.id;
 switch(act){case 'logout':return transaction(async()=>{await supabase.auth.signOut();store.user=null;store.role=null;location.hash='#/dashboard'},'Signed out');
 case 'new-proposal':overlay=formModal('create');render();return;
 case 'revise':overlay=formModal('revise',store.proposals.find(p=>p.id===id));render();return;
 case 'close-modal':overlay='';render();return;
 case 'proposal-detail':overlay=proposalModal(id);render();return;
 case 'detail':overlay=eventModal(id);render();return;
 case 'submit':return transaction(()=>call('submit_proposal',{p_proposal:id}),'Proposal submitted to lecturer');
 case 'publish':return transaction(()=>call('publish_proposal',{p_proposal:id}),'Approved event published to student dashboard and calendar');
 case 'join':return transaction(()=>call('apply_membership',{p_club:id}),'Membership application submitted');
 case 'register':return transaction(()=>call('register_event',{p_proposal:id}),'Registration created');
 case 'member-approve':return transaction(()=>call('decide_membership',{p_membership:id,p_approve:true}),'Membership approved');
 case 'member-reject':return transaction(()=>call('decide_membership',{p_membership:id,p_approve:false}),'Membership rejected');
 case 'checkout':return transaction(()=>checkout(el.dataset.kind,id));
 case 'qr':if(busy)return;wait(true);try{const raw=await call('issue_attendance_token',{p_proposal:id});const image=await QRCode.toDataURL(raw,{width:280,margin:2,errorCorrectionLevel:'M'});overlay=`<div class="modal-overlay" data-act="close-modal"><div class="modal qr-modal" onclick="event.stopPropagation()" role="dialog" aria-modal="true"><button class="modal-close" data-act="close-modal">×</button><span class="eyebrow teal">ONE-TIME ATTENDANCE PASS</span><h2>Show this QR to your organizer</h2><img src="${image}" alt="Attendance QR"/><p>Expires after 90 seconds. Single use only.</p><code>${esc(raw)}</code><button class="btn btn-light" data-act="close-modal">Close</button></div></div>`;render();}catch(e){toast(e.message,true)}finally{wait(false)}return;
 }}
async function onChange(event){if(event.target.id==='role-switch'){const role=event.target.value;if(!store.roles.includes(role))return toast('Role not assigned to your account',true);store.role=role;overlay='';location.hash='#/dashboard';try{await refresh();render()}catch(e){toast(e.message,true)}}}
function onInput(event){if(event.target.id==='event-search'){const query=event.target.value.toLowerCase().trim();document.querySelectorAll('.event-card').forEach(card=>card.style.display=card.textContent.toLowerCase().includes(query)?'':'none')}}
function onRoute(){overlay='';render();window.scrollTo({top:0,behavior:'instant'})}
app.addEventListener('submit',onSubmit);app.addEventListener('click',onClick);app.addEventListener('change',onChange);app.addEventListener('input',onInput);
window.addEventListener('hashchange',onRoute);
if(supabase){supabase.auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT'){store.user=null;store.role=null;render()}})}
bootstrap();
