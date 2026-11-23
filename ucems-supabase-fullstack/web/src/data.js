import {supabase,get,call} from './client.js';
export const store={user:null,profile:null,roles:[],role:null,clubs:[],proposals:[],events:[],versions:[],reviewers:[],decisions:[],comments:[],memberships:[],registrations:[],badges:[],badgeCandidates:[],badgeAuthorizations:[],badgeProfiles:[],payments:[],refundRequests:[],eventCancellations:[],notifications:[],proposalDocuments:[],emailDomains:[],committee:[],organizers:[],committeePermissions:[],approvalAuthorities:[],approvalRules:[],approvalRuleRecipients:[],accounts:[],accountRoles:[],attendance:[],auditLogs:[],auditError:null,selectedProposal:null};
export const staffRoles=['committee','lecturer','authority','admin'];
export async function loadSession(){
 const {data:{user}}=await supabase.auth.getUser();store.user=user;
 if(!user){store.roles=[];store.role=null;return}
 const [roles,profiles]=await Promise.all([get('user_roles','role',q=>q.eq('user_id',user.id)),get('profiles','*',q=>q.eq('id',user.id))]);
 store.profile=profiles[0]||{full_name:user.email?.split('@')[0]};store.roles=roles.map(r=>r.role).filter(role=>role!=='organizer');
 if(!store.roles.includes(store.role))store.role=store.roles.includes('student')?'student':store.roles[0]||null;
}
export async function refresh({strict=false}={}){
 if(!store.user)return;
 const safe=async(f,key)=>{try{return await f()}catch(e){if(strict)throw e;if(key==='audit')store.auditError=e.message;console.warn('Fetch',e.message);return []}};
 const [clubs,proposals,versions,reviewers,decisions,comments,memberships,registrations,badges,badgeCandidates,badgeAuthorizations,badgeProfiles,payments,refundRequests,eventCancellations,committee,organizers,attendance,committeePermissions,notifications,proposalDocuments]=await Promise.all([
 safe(()=>get('clubs')),safe(()=>get('proposals')),safe(()=>get('proposal_versions')),safe(()=>get('proposal_authority_assignments')),safe(()=>get('review_decisions')),safe(()=>get('proposal_comments')),safe(()=>get('memberships')),safe(()=>get('registrations')),safe(()=>get('badges')),safe(()=>get('badge_candidates')),safe(()=>get('badge_authorizations')),safe(()=>get('profiles','id,full_name')),safe(()=>get('payment_orders','*',query=>query.order('created_at',{ascending:false}).limit(100))),safe(()=>get('refund_requests','*',query=>query.order('created_at',{ascending:false}).limit(100))),safe(()=>get('event_cancellations','*',query=>query.order('created_at',{ascending:false}).limit(100))),safe(()=>get('committee_seats')),safe(()=>get('club_organizers')),safe(()=>get('attendance')),safe(()=>get('committee_position_permissions')),safe(()=>get('notifications','id,event_key,summary,entity_type,entity_id,created_at,read_at',query=>query.order('created_at',{ascending:false}).limit(50))),safe(()=>get('proposal_documents','id,proposal_id,version,uploaded_by,object_path,file_name,mime_type,file_size_bytes,created_at',query=>query.order('created_at',{ascending:true})))
 ]);
 Object.assign(store,{clubs,proposals,versions,reviewers:reviewers.map(({reviewer_id,...assignment})=>({...assignment,user_id:reviewer_id})),decisions,comments,memberships,registrations,badges,badgeCandidates,badgeAuthorizations,badgeProfiles,payments,refundRequests,eventCancellations,notifications,proposalDocuments,committee,organizers,attendance,committeePermissions});
 store.events=proposals.map(p=>{const publishedVersion=p.published_version||(p.status==='published'?p.current_version:null);return publishedVersion?{...p,version:versions.find(v=>v.proposal_id===p.id&&v.version===publishedVersion)}:null}).filter(x=>x?.version);
 if(store.role==='admin'){
  store.auditError=null;
  const [accounts,accountRoles,approvalAuthorities,auditLogs,emailDomains,approvalRules,approvalRuleRecipients]=await Promise.all([
   safe(()=>get('profiles')),
   safe(()=>get('user_roles')),
   safe(()=>get('authority_routing_recipients')),
   safe(()=>get('audit_log','id,actor_id,entity_type,entity_id,action,details,created_at',query=>query.order('created_at',{ascending:false}).limit(100)),'audit'),
   safe(()=>get('allowed_email_domains','domain')),
   safe(()=>get('authority_routing_rules','*',query=>query.order('name'))),
   safe(()=>get('authority_routing_rule_recipients'))
  ]);
  Object.assign(store,{accounts,accountRoles,approvalAuthorities,auditLogs,emailDomains,approvalRules,approvalRuleRecipients});
 }else{
  store.accounts=[];store.accountRoles=[];store.approvalAuthorities=[];store.approvalRules=[];store.approvalRuleRecipients=[];store.auditLogs=[];store.emailDomains=[];store.auditError=null;
 }
}
export const vOf=p=>store.versions.find(v=>v.proposal_id===p?.id&&v.version===p.current_version);
export const clubOf=id=>store.clubs.find(c=>c.id===id);
export const ownClubIds=()=>store.committee.filter(x=>x.user_id===store.user?.id).map(x=>x.club_id);
export const organizerClubIds=()=>[...new Set([...ownClubIds(),...store.organizers.filter(x=>x.user_id===store.user?.id).map(x=>x.club_id)])];
export async function doRpc(name,params){return call(name,params)}
export async function checkout(kind,ref){const {data,error}=await supabase.functions.invoke('create-checkout',{body:{kind,reference_id:ref}});if(error||data?.error)throw Error(data?.error||error?.message);if(!data?.url)throw Error('Payment gateway not configured');window.location.href=data.url}
