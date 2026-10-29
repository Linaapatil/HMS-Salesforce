// Generates permission sets, profiles, record types, layouts, compact layouts, tabs, roles, groups and sharing rules
// from the field metadata in force-app. Usage: node scripts/generate/security-and-layouts.js . <admin-username>
const fs = require('fs');
const path = require('path');
const ROOT = process.argv[2];
const D = path.join(ROOT, 'force-app/main/default');
const ADMIN_USER = process.argv[3];
const w = (rel, content) => {
  const p = path.join(D, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, '<?xml version="1.0" encoding="UTF-8"?>\n' + content.trim() + '\n');
};
const x = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const rtVal = (v) => encodeURIComponent(v).replace(/%20/g, ' ');

const OBJECTS = ['Patient__c', 'Doctor__c', 'Appointment__c', 'Department__c', 'Billing__c', 'Medical_Record__c', 'Lab_Result__c', 'Procedure__c', 'Patient_Procedure__c'];

// ---------- read fields ----------
const fields = {};
const picklists = {};
for (const o of OBJECTS) {
  fields[o] = [];
  const dir = path.join(D, 'objects', o, 'fields');
  for (const f of fs.readdirSync(dir)) {
    const xml = fs.readFileSync(path.join(dir, f), 'utf8');
    const name = /<fullName>([^<]+)<\/fullName>/.exec(xml)[1];
    const type = /<type>([^<]+)<\/type>/.exec(xml)[1];
    const required = /<required>true<\/required>/.test(xml);
    const formula = /<formula>/.test(xml);
    fields[o].push({ name, type, required, readOnly: formula || type === 'Summary' || type === 'AutoNumber', skip: type === 'MasterDetail' || required });
    if (type === 'Picklist') {
      picklists[o + '.' + name] = [...xml.matchAll(/<value>\s*<fullName>([^<]+)<\/fullName>/g)].map((m) => m[1].replace(/&amp;/g, '&'));
    }
  }
  fields[o].sort((a, b) => a.name.localeCompare(b.name));
}

// ---------- record types ----------
const RECORD_TYPES = {
  Patient__c: [
    { name: 'Outpatient', label: 'Outpatient', desc: 'Patients visiting for consultation without admission.' },
    { name: 'Inpatient', label: 'Inpatient', desc: 'Admitted patients occupying a bed.' },
    { name: 'Emergency', label: 'Emergency', desc: 'Emergency / casualty patients.', defaults: { Primary_Department__c: 'Emergency Medicine' } }
  ],
  Appointment__c: [
    { name: 'General_Consultation', label: 'General Consultation', desc: 'Routine consultation.', only: { Appointment_Type__c: ['General Consultation'] }, defaults: { Appointment_Type__c: 'General Consultation', Status__c: 'Requested' } },
    { name: 'Specialist_Consultation', label: 'Specialist Consultation', desc: 'Consultation with a specialist.', only: { Appointment_Type__c: ['Specialist Consultation'] }, defaults: { Appointment_Type__c: 'Specialist Consultation', Status__c: 'Requested', Specialist_Required__c: 'Yes' } },
    { name: 'Emergency', label: 'Emergency', desc: 'Emergency appointment.', only: { Appointment_Type__c: ['Emergency'] }, defaults: { Appointment_Type__c: 'Emergency', Status__c: 'Confirmed' } }
  ]
};
const allRecordTypes = [];
for (const [o, rts] of Object.entries(RECORD_TYPES)) {
  for (const rt of rts) {
    allRecordTypes.push(o + '.' + rt.name);
    const pls = Object.keys(picklists).filter((k) => k.startsWith(o + '.'));
    const body = pls
      .map((k) => {
        const f = k.split('.')[1];
        const vals = (rt.only && rt.only[f]) || picklists[k];
        const def = rt.defaults && rt.defaults[f];
        return `    <picklistValues>\n        <picklist>${f}</picklist>\n${vals.map((v) => `        <values>\n            <fullName>${x(rtVal(v))}</fullName>\n            <default>${v === def}</default>\n        </values>`).join('\n')}\n    </picklistValues>`;
      })
      .join('\n');
    w(`objects/${o}/recordTypes/${rt.name}.recordType-meta.xml`, `
<RecordType xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>${rt.name}</fullName>
    <active>true</active>
    <description>${x(rt.desc)}</description>
    <label>${x(rt.label)}</label>
${body}
</RecordType>`);
  }
}

// ---------- layouts ----------
const SYSTEM_SECTION = { label: 'System Information', cols: [['OwnerId:Edit', 'CreatedById:Readonly'], ['LastModifiedById:Readonly']] };
const rel = (child, field, cols) => ({ child, field, cols });
const LAYOUTS = {
  'Patient__c-Patient Layout': {
    sections: [
      { label: 'Patient Information', cols: [['Name:Readonly', 'Full_Name__c:Required', 'DOB__c', 'Age__c:Readonly', 'Blood_Group__c'], ['Primary_Department__c', 'RecordTypeId:Readonly', 'Last_Appointment_Date__c:Readonly']] },
      { label: 'Contact Details', cols: [['Phone__c', 'Email__c'], ['Address__c']] },
      { label: 'Emergency Contact', cols: [['Emergency_Contact_Name__c'], ['Emergency_Contact__c']] },
      { label: 'Insurance', cols: [['Insurance_Provider__c', 'Insurance_Policy_No__c'], ['SSN__c']] },
      { label: 'Summary', cols: [['Total_Appointments__c:Readonly'], ['Total_Billed_Amount__c:Readonly']] },
      SYSTEM_SECTION
    ],
    related: [
      rel('Appointment__c', 'Patient__c', ['NAME', 'Appointment_Date__c', 'Slot__c', 'Doctor__c', 'Status__c']),
      rel('Medical_Record__c', 'Patient__c', ['NAME', 'Diagnosis__c', 'Report_URL__c']),
      rel('Billing__c', 'Patient__c', ['NAME', 'Amount_Due__c', 'Status__c']),
      rel('Lab_Result__c', 'Patient__c', ['NAME', 'Test_Name__c', 'Status__c', 'Result_Date__c']),
      rel('Patient_Procedure__c', 'Patient__c', ['NAME'])
    ],
    actions: ['Patient__c.Schedule_Follow_up_Appointment', 'Patient__c.Send_Patient_Summary_Email', 'Edit']
  },
  'Patient__c-Patient Emergency Layout': {
    sections: [
      { label: 'Emergency Contact', cols: [['Emergency_Contact_Name__c:Required'], ['Emergency_Contact__c:Required']] },
      { label: 'Patient Information', cols: [['Name:Readonly', 'Full_Name__c:Required', 'DOB__c', 'Age__c:Readonly', 'Blood_Group__c'], ['Primary_Department__c', 'RecordTypeId:Readonly', 'Phone__c', 'Email__c']] },
      { label: 'Insurance', cols: [['Insurance_Provider__c', 'Insurance_Policy_No__c'], ['SSN__c']] },
      SYSTEM_SECTION
    ],
    related: [rel('Appointment__c', 'Patient__c', ['NAME', 'Appointment_Date__c', 'Slot__c', 'Doctor__c', 'Status__c']), rel('Medical_Record__c', 'Patient__c', ['NAME', 'Diagnosis__c']), rel('Billing__c', 'Patient__c', ['NAME', 'Amount_Due__c', 'Status__c'])],
    actions: ['Patient__c.Schedule_Follow_up_Appointment', 'Patient__c.Send_Patient_Summary_Email', 'Edit']
  },
  'Doctor__c-Doctor Layout': {
    sections: [
      { label: 'Doctor Information', cols: [['Name:Required', 'License_No__c:Required', 'Specialization__c', 'Department__c'], ['Status__c', 'Manager__c', 'Email__c', 'User__c']] },
      { label: 'Schedule', cols: [['Availability__c'], ['Active_Appointments__c:Readonly']] },
      SYSTEM_SECTION
    ],
    related: [
      rel('Appointment__c', 'Doctor__c', ['NAME', 'Appointment_Date__c', 'Slot__c', 'Patient__c', 'Status__c']),
      rel('Doctor__c', 'Manager__c', ['NAME', 'Specialization__c', 'Status__c']),
      rel('Department__c', 'HOD__c', ['NAME', 'Floor__c'])
    ]
  },
  'Appointment__c-Appointment Layout': appointmentLayout(false, false),
  'Appointment__c-Appointment Specialist Layout': appointmentLayout(true, false),
  'Appointment__c-Appointment Emergency Layout': appointmentLayout(false, false, true),
  'Appointment__c-Appointment Receptionist Layout': appointmentLayout(true, true),
  'Department__c-Department Layout': {
    sections: [{ label: 'Department Information', cols: [['Name:Required', 'Floor__c', 'HOD__c'], ['Bed_Count__c', 'Occupied_Beds__c', 'Bed_Occupancy__c:Readonly']] }, SYSTEM_SECTION],
    related: [rel('Doctor__c', 'Department__c', ['NAME', 'Specialization__c', 'Status__c', 'Active_Appointments__c'])]
  },
  'Billing__c-Billing Layout': {
    sections: [
      { label: 'Billing Information', cols: [['Name:Readonly', 'Appointment__c:Required', 'Patient__c', 'Procedure__c', 'Department_Name__c:Readonly'], ['Status__c', 'Insurance__c', 'Patient_Email__c']] },
      { label: 'Charges', cols: [['Total_Charges__c', 'Discount__c', 'Insurance_Coverage__c'], ['Insurance_Amount__c:Readonly', 'Amount_Due__c']] },
      { label: 'System Information', cols: [['CreatedById:Readonly'], ['LastModifiedById:Readonly']] }
    ],
    related: [],
    approvals: true
  },
  'Medical_Record__c-Medical Record Layout': {
    sections: [{ label: 'Medical Record', cols: [['Name:Readonly', 'Patient__c:Required', 'Report_URL__c'], []] }, { label: 'Clinical Notes', style: 'OneColumn', cols: [['Diagnosis__c', 'Prescription__c']] }, { label: 'System Information', cols: [['CreatedById:Readonly'], ['LastModifiedById:Readonly']] }],
    related: []
  },
  'Lab_Result__c-Lab Result Layout': {
    sections: [{ label: 'Lab Result', cols: [['Name:Readonly', 'Patient__c', 'Appointment__c'], ['Test_Name__c', 'Status__c', 'Result_Date__c']] }, { label: 'Result', style: 'OneColumn', cols: [['Result__c']] }, SYSTEM_SECTION],
    related: []
  },
  'Procedure__c-Procedure Layout': {
    sections: [{ label: 'Procedure', cols: [['Name:Required', 'Procedure_Code__c', 'Description__c'], ['Price__c', 'Base_Charge__c']] }, SYSTEM_SECTION],
    related: [rel('Patient_Procedure__c', 'Procedure__c', ['NAME'])]
  },
  'Patient_Procedure__c-Patient Procedure Layout': {
    sections: [{ label: 'Patient Procedure', cols: [['Name:Readonly', 'Patient__c:Required'], ['Procedure__c:Required']] }, { label: 'System Information', cols: [['CreatedById:Readonly'], ['LastModifiedById:Readonly']] }],
    related: []
  }
};
function appointmentLayout(specialist, receptionist, emergency) {
  return {
    sections: [
      {
        label: 'Appointment Details',
        cols: [
          ['Name:Readonly', 'Patient__c:Required', receptionist ? 'Doctor__c:Required' : 'Doctor__c', 'Department_Name__c:Readonly'],
          ['Appointment_Date__c:Required', 'Slot__c:Required', 'Status__c', 'RecordTypeId:Readonly']
        ]
      },
      { label: specialist ? 'Specialist Information' : emergency ? 'Emergency Details' : 'Consultation', cols: [['Appointment_Type__c'], specialist || emergency ? ['Specialist_Required__c'] : ['Is_Today__c:Readonly']] },
      { label: 'Contact', cols: [['Patient_Email__c'], []] },
      SYSTEM_SECTION
    ],
    related: [rel('Billing__c', 'Appointment__c', ['NAME', 'Amount_Due__c', 'Status__c']), rel('Lab_Result__c', 'Appointment__c', ['NAME', 'Test_Name__c', 'Status__c'])],
    activities: true
  };
}
for (const [name, l] of Object.entries(LAYOUTS)) {
  const obj = name.split('-')[0];
  const sec = l.sections
    .map((s) => {
      const style = s.style === 'OneColumn' ? 'OneColumn' : 'TwoColumnsTopToBottom';
      return `    <layoutSections>
        <customLabel>true</customLabel>
        <detailHeading>true</detailHeading>
        <editHeading>true</editHeading>
        <label>${x(s.label)}</label>
${s.cols
  .map((c) => (c.length ? `        <layoutColumns>\n${c.map((it) => { const [f, b] = it.split(':'); return `            <layoutItems>\n                <behavior>${b || 'Edit'}</behavior>\n                <field>${f}</field>\n            </layoutItems>`; }).join('\n')}\n        </layoutColumns>` : '        <layoutColumns/>'))
  .join('\n')}
        <style>${style}</style>
    </layoutSections>`;
    })
    .join('\n');
  const rels = l.related
    .map((r) => `    <relatedLists>\n${r.cols.map((c) => `        <fields>${c}</fields>`).join('\n')}\n        <relatedList>${r.child}.${r.field}</relatedList>\n    </relatedLists>`)
    .join('\n');
  const activity = `    <relatedLists>
        <fields>TASK.SUBJECT</fields>
        <fields>TASK.STATUS</fields>
        <fields>TASK.DUE_DATE</fields>
        <fields>CORE.USERS.FULL_NAME</fields>
        <relatedList>RelatedActivityList</relatedList>
    </relatedLists>
    <relatedLists>
        <fields>TASK.SUBJECT</fields>
        <fields>TASK.DUE_DATE</fields>
        <fields>CORE.USERS.FULL_NAME</fields>
        <relatedList>RelatedHistoryList</relatedList>
    </relatedLists>`;
  const approvals = l.approvals ? `    <relatedLists>\n        <relatedList>RelatedProcessHistoryList</relatedList>\n    </relatedLists>` : '';
  // Explicit actions so record pages don't inherit unrelated global actions (New Contact, New Case...).
  l.actions = l.actions || (l.approvals ? ['Edit', 'Submit', 'Clone', 'Delete'] : ['Edit', 'Clone', 'Delete']);
  const actions = l.actions
    ? `    <platformActionList>
        <actionListContext>Record</actionListContext>
${l.actions.map((a, i) => `        <platformActionListItems>\n            <actionName>${a}</actionName>\n            <actionType>${a.includes('.') ? 'QuickAction' : 'StandardButton'}</actionType>\n            <sortOrder>${i}</sortOrder>\n        </platformActionListItems>`).join('\n')}
    </platformActionList>`
    : '';
  const hasActivities = !['Billing__c', 'Medical_Record__c', 'Patient_Procedure__c'].includes(obj);
  w(`layouts/${name}.layout-meta.xml`, `
<Layout xmlns="http://soap.sforce.com/2006/04/metadata">
${sec}
    <layoutSections>
        <customLabel>false</customLabel>
        <detailHeading>false</detailHeading>
        <editHeading>true</editHeading>
        <layoutColumns/>
        <layoutColumns/>
        <layoutColumns/>
        <style>CustomLinks</style>
    </layoutSections>
${actions}
${rels}
${hasActivities ? activity : ''}
${approvals}
    <showEmailCheckbox>false</showEmailCheckbox>
    <showHighlightsPanel>false</showHighlightsPanel>
    <showInteractionLogPanel>false</showInteractionLogPanel>
    <showRunAssignmentRulesCheckbox>false</showRunAssignmentRulesCheckbox>
    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>
</Layout>`.replace(/\n\n+/g, '\n'));
}

// ---------- compact layouts (record page highlights) ----------
const COMPACT = {
  Patient__c: ['Name', 'Full_Name__c', 'RecordTypeId', 'Primary_Department__c', 'Blood_Group__c', 'Phone__c'],
  Doctor__c: ['Name', 'Specialization__c', 'Department__c', 'Status__c', 'Active_Appointments__c'],
  Appointment__c: ['Name', 'Patient_Name__c', 'Doctor__c', 'Appointment_Date__c', 'Slot__c', 'Status__c'],
  Billing__c: ['Name', 'Patient__c', 'Status__c', 'Total_Charges__c', 'Amount_Due__c']
};
for (const [o, flds] of Object.entries(COMPACT)) {
  w(`objects/${o}/compactLayouts/HMS_Compact.compactLayout-meta.xml`, `
<CompactLayout xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>HMS_Compact</fullName>
${flds.map((f) => `    <fields>${f}</fields>`).join('\n')}
    <label>HMS Compact</label>
</CompactLayout>`);
  const objFile = path.join(D, 'objects', o, o + '.object-meta.xml');
  let objXmlText = fs.readFileSync(objFile, 'utf8');
  if (!objXmlText.includes('<compactLayoutAssignment>')) {
    objXmlText = objXmlText.replace('<deploymentStatus>', '<compactLayoutAssignment>HMS_Compact</compactLayoutAssignment>\n    <deploymentStatus>');
    fs.writeFileSync(objFile, objXmlText);
  }
}

// ---------- tabs ----------
const TAB_MOTIFS = {
  Patient__c: 'Custom1: Heart',
  Doctor__c: 'Custom15: People',
  Appointment__c: 'Custom95: Calendar',
  Department__c: 'Custom24: Buildings',
  Billing__c: 'Custom41: Bank',
  Medical_Record__c: 'Custom18: Form',
  Lab_Result__c: 'Custom39: Microscope',
  Procedure__c: 'Custom19: Wrench',
  Patient_Procedure__c: 'Custom57: Building'
};
for (const o of OBJECTS) {
  w(`tabs/${o}.tab-meta.xml`, `
<CustomTab xmlns="http://soap.sforce.com/2006/04/metadata">
    <customObject>true</customObject>
    <motif>${TAB_MOTIFS[o]}</motif>
</CustomTab>`);
}
const TABS = ['HMS_Home', ...OBJECTS];

// ---------- classes ----------
const classes = fs
  .readdirSync(path.join(D, 'classes'))
  .filter((f) => f.endsWith('.cls'))
  .map((f) => f.replace('.cls', ''))
  .filter((c) => !/Test$|TestDataFactory|Mock$/.test(c));

// ---------- permission sets ----------
const ALL = { c: true, r: true, e: true, d: true, va: true, ma: true };
const CRE = { c: true, r: true, e: true };
const CRED = { c: true, r: true, e: true, d: true };
const R = { r: true };
const RE = { r: true, e: true };
function objXml(objPerms) {
  return Object.entries(objPerms)
    .map(([o, p]) => `    <objectPermissions>
        <allowCreate>${!!p.c}</allowCreate>
        <allowDelete>${!!p.d}</allowDelete>
        <allowEdit>${!!p.e}</allowEdit>
        <allowRead>${!!p.r}</allowRead>
        <modifyAllRecords>${!!p.ma}</modifyAllRecords>
        <object>${o}</object>
        <viewAllRecords>${!!p.va}</viewAllRecords>
    </objectPermissions>`)
    .join('\n');
}
function fieldXml(objPerms, overrides = {}) {
  const out = [];
  for (const o of OBJECTS) {
    for (const f of fields[o]) {
      if (f.skip) continue;
      const key = o + '.' + f.name;
      const p = objPerms[o];
      let readable = !!(p && p.r);
      let editable = !!(p && (p.e || p.c)) && !f.readOnly;
      if (key in overrides) {
        readable = overrides[key].r;
        editable = overrides[key].e && !f.readOnly;
      }
      if (!readable && !(key in overrides)) continue;
      out.push(`    <fieldPermissions>\n        <editable>${editable}</editable>\n        <field>${key}</field>\n        <readable>${readable}</readable>\n    </fieldPermissions>`);
    }
  }
  return out.join('\n');
}
function rtXml(objPerms, tag = 'recordTypeVisibilities', withDefault = false) {
  return allRecordTypes
    .filter((rt) => objPerms[rt.split('.')[0]])
    .map((rt) => {
      const def = withDefault && /Outpatient|General_Consultation/.test(rt);
      return `    <${tag}>\n${withDefault ? `        <default>${def}</default>\n` : ''}        <recordType>${rt}</recordType>\n        <visible>true</visible>\n    </${tag}>`;
    })
    .join('\n');
}
function tabXml(objPerms, tag, includeHome) {
  const vis = tag === 'tabVisibilities' ? 'DefaultOn' : 'Visible';
  return TABS.filter((t) => (t === 'HMS_Home' ? includeHome : objPerms[t]))
    .map((t) => `    <${tag}>\n        <tab>${t}</tab>\n        <visibility>${vis}</visibility>\n    </${tag}>`)
    .join('\n');
}
function classXml(list) {
  return list.map((c) => `    <classAccesses>\n        <apexClass>${c}</apexClass>\n        <enabled>true</enabled>\n    </classAccesses>`).join('\n');
}
const PERMSETS = {
  HMS_Hospital_Admin: {
    label: 'HMS Hospital Admin',
    desc: 'Full access to all Hospital Management System objects, fields, Apex and the MedCare app.',
    objects: Object.fromEntries(OBJECTS.map((o) => [o, ALL])),
    classes,
    home: true,
    principals: ['LabSystem_EC-LabPrincipal', 'Insurance_EC-InsurancePrincipal']
  },
  HMS_Doctor_Access: {
    label: 'HMS Doctor Access',
    desc: 'Doctor_Profile permissions as a permission set: read/write Appointments, read Patients, no Billing.',
    objects: { Appointment__c: CRE, Patient__c: R, Doctor__c: R, Department__c: R, Medical_Record__c: CRE, Procedure__c: R, Patient_Procedure__c: CRE },
    classes: ['AppointmentScheduler', 'PatientService', 'HospitalDashboardController', 'EmailService', 'HospitalException'],
    home: true
  },
  HMS_Lab_Access: {
    label: 'HMS Lab Access',
    desc: 'Lab results and the external lab system integration.',
    objects: { Lab_Result__c: CRED, Patient__c: R, Medical_Record__c: RE },
    classes: ['LabIntegrationService', 'LabResultProcessor', 'HospitalException'],
    home: false,
    principals: ['LabSystem_EC-LabPrincipal']
  },
  HMS_Receptionist_Access: {
    label: 'HMS Receptionist Access',
    desc: 'Create/edit Patients and Appointments. SSN is read-only. No Apex class access.',
    objects: { Patient__c: CRE, Appointment__c: CRE, Doctor__c: R, Department__c: R },
    overrides: { 'Patient__c.SSN__c': { r: true, e: false } },
    classes: [],
    home: false
  },
  Billing_Manager: {
    label: 'Billing Manager',
    desc: 'Assign to the Accounts team for billing access.',
    objects: { Billing__c: CRED, Procedure__c: CRED, Appointment__c: R, Patient__c: R, Doctor__c: R, Department__c: R },
    classes: ['BillingCalculator', 'SendInsuranceClaimAsync', 'InsuranceVerificationService', 'MonthlyBillingReport', 'HospitalDashboardController', 'HospitalException'],
    home: true,
    principals: ['Insurance_EC-InsurancePrincipal']
  }
};
for (const [name, ps] of Object.entries(PERMSETS)) {
  w(`permissionsets/${name}.permissionset-meta.xml`, `
<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>${x(ps.desc)}</description>
${name === 'HMS_Hospital_Admin' ? `    <applicationVisibilities>\n        <application>MedCare_HMS</application>\n        <visible>true</visible>\n    </applicationVisibilities>` : ''}
${classXml(ps.classes)}
${(ps.principals || []).map((p) => `    <externalCredentialPrincipalAccesses>\n        <enabled>true</enabled>\n        <externalCredentialPrincipal>${p}</externalCredentialPrincipal>\n    </externalCredentialPrincipalAccesses>`).join('\n')}
${fieldXml(ps.objects, ps.overrides)}
    <hasActivationRequired>false</hasActivationRequired>
    <label>${x(ps.label)}</label>
${objXml(ps.objects)}
${rtXml(ps.objects)}
${tabXml(ps.objects, 'tabSettings', ps.home)}
</PermissionSet>`.replace(/\n\n+/g, '\n'));
}
w('permissionsetgroups/Doctor_Extended.permissionsetgroup-meta.xml', `
<PermissionSetGroup xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>Doctor_Profile permissions plus Lab access.</description>
    <label>Doctor Extended</label>
    <permissionSets>HMS_Doctor_Access</permissionSets>
    <permissionSets>HMS_Lab_Access</permissionSets>
    <status>Updated</status>
</PermissionSetGroup>`);

// ---------- profiles ----------
const LAYOUT_ASSIGN = (receptionist) => {
  const a = [];
  const add = (layout, rt) => a.push(`    <layoutAssignments>\n        <layout>${layout}</layout>\n${rt ? `        <recordType>${rt}</recordType>\n` : ''}    </layoutAssignments>`);
  for (const o of OBJECTS) {
    if (o === 'Appointment__c' || o === 'Patient__c') continue;
    add(Object.keys(LAYOUTS).find((k) => k.startsWith(o + '-')));
  }
  add('Patient__c-Patient Layout');
  add('Patient__c-Patient Layout', 'Patient__c.Outpatient');
  add('Patient__c-Patient Layout', 'Patient__c.Inpatient');
  add('Patient__c-Patient Emergency Layout', 'Patient__c.Emergency');
  if (receptionist) {
    add('Appointment__c-Appointment Receptionist Layout');
    for (const rt of RECORD_TYPES.Appointment__c) add('Appointment__c-Appointment Receptionist Layout', 'Appointment__c.' + rt.name);
  } else {
    add('Appointment__c-Appointment Layout');
    add('Appointment__c-Appointment Layout', 'Appointment__c.General_Consultation');
    add('Appointment__c-Appointment Specialist Layout', 'Appointment__c.Specialist_Consultation');
    add('Appointment__c-Appointment Emergency Layout', 'Appointment__c.Emergency');
  }
  return a.join('\n');
};
const PROFILES = {
  Hospital_Admin: { ps: 'HMS_Hospital_Admin', custom: true, desc: 'Hospital administrators: full access to all custom objects.' },
  Doctor_Profile: { ps: 'HMS_Doctor_Access', custom: true, desc: 'Doctors: read/write Appointments, read Patients, no access to Billing.', overrides: { 'Billing__c.Insurance_Amount__c': { r: false, e: false } } },
  Receptionist_Profile: { ps: 'HMS_Receptionist_Access', custom: true, desc: 'Receptionists: create/edit Appointments and Patients, no Apex classes.', receptionist: true },
  Admin: { ps: 'HMS_Hospital_Admin', custom: false }
};
for (const [name, pr] of Object.entries(PROFILES)) {
  const ps = PERMSETS[pr.ps];
  const overrides = Object.assign({}, ps.overrides || {}, pr.overrides || {});
  w(`profiles/${name}.profile-meta.xml`, `
<Profile xmlns="http://soap.sforce.com/2006/04/metadata">
    <applicationVisibilities>
        <application>MedCare_HMS</application>
        <default>${pr.custom}</default>
        <visible>true</visible>
    </applicationVisibilities>
${classXml(ps.classes)}
    <custom>${pr.custom}</custom>
${pr.desc ? `    <description>${x(pr.desc)}</description>` : ''}
${fieldXml(ps.objects, overrides)}
${LAYOUT_ASSIGN(pr.receptionist)}
${objXml(ps.objects)}
${rtXml(ps.objects, 'recordTypeVisibilities', true)}
${tabXml(ps.objects, 'tabVisibilities', ps.home || pr.custom)}
${pr.custom ? '    <userLicense>Salesforce</userLicense>' : ''}
${pr.custom ? ['ApiEnabled', 'RunReports', 'ExportReport', 'ActivitiesAccess', 'ChatterInternalUser', 'LightningExperienceUser', 'ViewHelpLink', 'EditTask', 'EditEvent', 'ShowCompanyNameAsUserBadge', 'AllowViewKnowledge'].filter((p) => !(p === 'ViewSetup' && name !== 'Hospital_Admin')).map((p) => `    <userPermissions>\n        <enabled>true</enabled>\n        <name>${p}</name>\n    </userPermissions>`).join('\n') : ''}
</Profile>`.replace(/\n\n+/g, '\n'));
}

// ---------- roles ----------
const ROLES = [
  ['CEO', 'CEO', null],
  ['Hospital_Admin', 'Hospital Admin', 'CEO'],
  ['Department_Head', 'Department Head', 'Hospital_Admin'],
  ['Doctor', 'Doctor', 'Department_Head'],
  ['Receptionist', 'Receptionist', 'Doctor']
];
for (const [n, l, p] of ROLES) {
  w(`roles/${n}.role-meta.xml`, `
<Role xmlns="http://soap.sforce.com/2006/04/metadata">
    <caseAccessLevel>Edit</caseAccessLevel>
    <mayForecastManagerShare>false</mayForecastManagerShare>
    <name>${l}</name>
    <opportunityAccessLevel>Edit</opportunityAccessLevel>
${p ? `    <parentRole>${p}</parentRole>` : ''}
</Role>`.replace(/\n\n+/g, '\n'));
}

// ---------- groups + sharing rules ----------
const DEPTS = picklists['Patient__c.Primary_Department__c'];
const groups = [['On_Call_Doctors', 'On-Call Doctors'], ['Billing_Team', 'Billing Team'], ...DEPTS.filter((d) => d !== 'Emergency Medicine').map((d) => ['Dept_' + d.replace(/\s+/g, '_') + '_Doctors', d + ' Doctors'])];
for (const [n, l] of groups) {
  w(`groups/${n}.group-meta.xml`, `
<Group xmlns="http://soap.sforce.com/2006/04/metadata">
    <doesIncludeBosses>true</doesIncludeBosses>
    <name>${l}</name>
</Group>`);
}
const rules = DEPTS.map((d) => {
  const isEmergency = d === 'Emergency Medicine';
  const group = isEmergency ? 'On_Call_Doctors' : 'Dept_' + d.replace(/\s+/g, '_') + '_Doctors';
  const name = isEmergency ? 'Share_Emergency_Patients_With_On_Call' : 'Share_' + d.replace(/\s+/g, '_') + '_Patients';
  return `    <sharingCriteriaRules>
        <fullName>${name}</fullName>
        <accessLevel>${isEmergency ? 'Edit' : 'Read'}</accessLevel>
        <description>${x(isEmergency ? 'Emergency patients are shared with the on-call doctor group.' : 'Share ' + d + ' patients with doctors of the same department.')}</description>
        <label>${x(isEmergency ? 'Share Emergency Patients With On-Call' : 'Share ' + d + ' Patients')}</label>
        <sharedTo>
            <group>${group}</group>
        </sharedTo>
        <criteriaItems>
            <field>Primary_Department__c</field>
            <operation>equals</operation>
            <value>${x(d)}</value>
        </criteriaItems>
        <includeRecordsOwnedByAll>true</includeRecordsOwnedByAll>
    </sharingCriteriaRules>`;
}).join('\n');
w('sharingRules/Patient__c.sharingRules-meta.xml', `
<SharingRules xmlns="http://soap.sforce.com/2006/04/metadata">
${rules}
</SharingRules>`);

console.log('record types', allRecordTypes.length, 'layouts', Object.keys(LAYOUTS).length, 'permsets', Object.keys(PERMSETS).length, 'classes', classes.length, 'groups', groups.length);
