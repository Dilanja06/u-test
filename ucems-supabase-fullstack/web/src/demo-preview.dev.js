import { store } from './data.js';

const demoAccounts = [
  { id: 'demo-admin', name: 'Demo Administrator', email: 'admin.demo@example.test', role: 'admin' },
  { id: 'demo-student', name: 'Demo Student', email: 'student.demo@example.test', role: 'student' },
  { id: 'demo-committee', name: 'Demo Committee Member', email: 'committee.demo@example.test', role: 'committee' },
  { id: 'demo-coordinator', name: 'Demo Club Coordinator', email: 'coordinator.demo@example.test', role: 'lecturer' },
  { id: 'demo-authority', name: 'Demo Higher Authority', email: 'authority.demo@example.test', role: 'authority' },
];

const clubId = 'demo-club';
const demoPermissionKeys = [
  'club.profile.edit','club.members.view','club.members.manage','event.create','event.edit_draft',
  'event.proposal.submit','event.change.request','event.publish','event.unpublish','event.cancel',
  'proposal.review.club','proposal.comment','registration.view','registration.verify_external',
  'registration.export','attendance.scan','attendance.view','badge.nominate','badge.authorize',
  'badge.definitions.manage','finance.view','finance.refund.approve','finance.reconcile',
  'finance.export','club.reporting.view',
];
const demoProposals = [
  { id: 'demo-draft', status: 'draft', title: 'Spring Coding Workshop' },
  { id: 'demo-lecturer-review', status: 'lecturer_pending', title: 'Campus Innovation Night' },
  { id: 'demo-authority-review', status: 'authority_pending', title: 'Community Tech Fair', current_version: 2 },
  { id: 'demo-published', status: 'published', title: 'Welcome Week Social' },
];

function futureDate(days, hours = 0) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(date.getHours() + hours);
  return date.toISOString();
}

function versionFor(proposal, version = 1) {
  return {
    proposal_id: proposal.id,
    version,
    title: version === 1 && proposal.id === 'demo-authority-review' ? 'Community Tech Fair' : proposal.title,
    description: `Preview data for Version ${version} of ${proposal.title.toLowerCase()}.`,
    starts_at: futureDate(7, 2),
    ends_at: futureDate(7, 4),
    venue: version === 1 ? 'Main Campus Hall' : 'Innovation Hall',
    capacity: version === 1 ? 120 : 150,
    fee_cents: 0,
    created_at: new Date(Date.now() - (version === 1 ? 86400000 * 2 : 86400000)).toISOString(),
  };
}

export function loadDemoPreview(role) {
  const account = demoAccounts.find(item => item.role === role);
  if (!account) throw new Error('Unknown demo role.');

  const proposals = demoProposals.map(proposal => ({
    id: proposal.id,
    club_id: clubId,
    created_by: 'demo-committee',
    current_version: proposal.current_version || 1,
    status: proposal.status,
    published_at: proposal.status === 'published' ? new Date().toISOString() : null,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }));
  const versions = demoProposals.flatMap(proposal=>
    Array.from({length:proposal.current_version||1},(_,index)=>versionFor(proposal,index+1))
  );
  const publishedProposal = proposals.find(proposal => proposal.id === 'demo-published');
  const publishedVersion = versions.find(version => version.proposal_id === 'demo-published');

  Object.assign(store, {
    user: { id: account.id, email: account.email },
    profile: { id: account.id, full_name: account.name },
    roles: [role],
    role,
    clubs: [{
      id: clubId,
      name: 'UCEMS Demo Club',
      description: 'Sample club for exploring the campus event workflow.',
      category: 'Technology',
      membership_fee_cents: 0,
      lecturer_id: 'demo-coordinator',
    }],
    proposals,
    events: [{ ...publishedProposal, version: publishedVersion }],
    versions,
    reviewers: [{ proposal_id: 'demo-authority-review', version: 2, user_id: 'demo-authority' }],
    decisions: [{
      id: 'demo-lecturer-decision-v1',
      proposal_id: 'demo-authority-review',
      version: 1,
      reviewer_id: 'demo-coordinator',
      stage: 'lecturer',
      decision: 'changes_requested',
      comment: 'Please confirm the event venue and capacity.',
      created_at: new Date(Date.now() - 86400000 * 2).toISOString(),
    },{
      id: 'demo-lecturer-decision-v2',
      proposal_id: 'demo-authority-review',
      version: 2,
      reviewer_id: 'demo-coordinator',
      stage: 'lecturer',
      decision: 'approved',
      comment: 'The revised venue and capacity are approved.',
      created_at: new Date(Date.now() - 86400000).toISOString(),
    }],
    comments: [{
      id: 'demo-comment-v2',
      proposal_id: 'demo-authority-review',
      version: 2,
      author_id: 'demo-committee',
      body: 'Version 2 updates the venue and capacity as requested.',
      created_at: new Date(Date.now() - 43200000).toISOString(),
    }],
    memberships: [{
      id: 'demo-membership',
      club_id: clubId,
      user_id: 'demo-student',
      status: 'active',
      created_at: new Date(Date.now() - 86400000 * 10).toISOString(),
    }],
    registrations: [{
      id: 'demo-registration',
      proposal_id: 'demo-published',
      user_id: 'demo-student',
      status: 'registered',
      created_at: new Date(Date.now() - 86400000 * 2).toISOString(),
    }],
    badges: [{
      id: 'demo-badge',
      proposal_id: 'demo-published',
      user_id: 'demo-student',
      issued_at: new Date().toISOString(),
      authorized_by: 'demo-committee',
    }],
    badgeCandidates: [],
    badgeAuthorizations: [],
    badgeProfiles: demoAccounts.map(({ id, name }) => ({ id, full_name: name })),
    payments: [],
    committee: [{ club_id: clubId, seat: 1, position_name: 'President', user_id: 'demo-committee' }],
    organizers: [],
    committeePermissions: demoPermissionKeys.map(permission_key => ({
      club_id: clubId,
      position_name: 'President',
      permission_key,
      enabled: true,
    })),
    approvalAuthorities: [{ user_id: 'demo-authority' }],
    accounts: demoAccounts.map(({ id, name }) => ({ id, full_name: name })),
    accountRoles: demoAccounts.map(({ id, role }) => ({ user_id: id, role })),
    attendance: [],
    auditLogs: role==='admin'?[{
      id: 1,
      actor_id: 'demo-admin',
      entity_type: 'committee_permission',
      entity_id: clubId,
      action: 'permission_updated',
      details: {position:'President',permission:'event.create',enabled:true},
      created_at: new Date().toISOString(),
    }]:[],
    auditError: null,
    selectedProposal: null,
  });
}
