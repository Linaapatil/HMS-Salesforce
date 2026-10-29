// Generates the MedCare HMS app, Lightning pages, Path, reports and the admin dashboard.
// Usage: node scripts/generate/app-pages-reports.js . <admin-username>
const fs = require('fs');
const path = require('path');
const D = path.join(process.argv[2], 'force-app/main/default');
const ADMIN_USER = process.argv[3];
const w = (rel, content) => {
  const p = path.join(D, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, '<?xml version="1.0" encoding="UTF-8"?>\n' + content.trim().replace(/\n\s*\n/g, '\n') + '\n');
};
const x = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// ---------- extra formula field ----------
w('objects/Appointment__c/fields/Patient_Name__c.field-meta.xml', `
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Patient_Name__c</fullName>
    <label>Patient Name</label>
    <formula>Patient__r.Full_Name__c</formula>
    <formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>`);

// ---------- flexipages ----------
let ids = 0;
const comp = (name, props = {}) => `
            <componentInstance>
${Object.entries(props).map(([k, v]) => `                <componentInstanceProperties>\n                    <name>${k}</name>\n                    <value>${x(v)}</value>\n                </componentInstanceProperties>`).join('\n')}
                <componentName>${name}</componentName>
                <identifier>${name.replace(/[^A-Za-z0-9]/g, '_')}_${++ids}</identifier>
            </componentInstance>`;
const region = (name, comps) => `
    <flexiPageRegions>
${comps.map((c) => `        <itemInstances>${c}\n        </itemInstances>`).join('\n')}
        <name>${name}</name>
        <type>Region</type>
    </flexiPageRegions>`;

w('flexipages/HMS_Home.flexipage-meta.xml', `
<FlexiPage xmlns="http://soap.sforce.com/2006/04/metadata">
${region('main', [comp('c:patientSearchBar'), comp('c:hospitalDashboard')])}
    <masterLabel>HMS Home</masterLabel>
    <template>
        <name>flexipage:defaultAppHomeTemplate</name>
    </template>
    <type>AppPage</type>
</FlexiPage>`);

const recordPage = (name, label, obj, header, main, sidebar) => w(`flexipages/${name}.flexipage-meta.xml`, `
<FlexiPage xmlns="http://soap.sforce.com/2006/04/metadata">
${region('header', header)}
${region('main', main)}
${region('sidebar', sidebar)}
    <masterLabel>${x(label)}</masterLabel>
    <sobjectType>${obj}</sobjectType>
    <template>
        <name>flexipage:recordHomeTemplateDesktop</name>
    </template>
    <type>RecordPage</type>
</FlexiPage>`);

const highlights = () => comp('force:highlightsPanel', { collapsed: 'false', numVisibleActions: '4' });
recordPage('Patient_Record_Page', 'Patient Record Page', 'Patient__c', [highlights()], [comp('force:detailPanel')], [comp('force:relatedListContainer')]);
recordPage(
  'Patient_Emergency_Record_Page',
  'Patient Emergency Record Page',
  'Patient__c',
  [highlights(), comp('flexipage:richText', { richTextValue: '<p style="text-align:center;"><b style="color:#b42318;font-size:16px;">EMERGENCY PATIENT - shared with the On-Call Doctors group</b></p>' })],
  [comp('force:detailPanel')],
  [comp('force:relatedListContainer')]
);
recordPage('Doctor_Record_Page', 'Doctor Record Page', 'Doctor__c', [highlights()], [comp('c:doctorScheduleCard', { cardTitle: "Today's Schedule" }), comp('force:detailPanel')], [comp('force:relatedListContainer')]);
recordPage('Appointment_Record_Page', 'Appointment Record Page', 'Appointment__c', [highlights(), comp('runtime_sales_pathassistant:pathAssistant')], [comp('force:detailPanel')], [comp('force:relatedListContainer')]);

w('tabs/HMS_Home.tab-meta.xml', `
<CustomTab xmlns="http://soap.sforce.com/2006/04/metadata">
    <description>MedCare HMS home: patient search, admin dashboard, doctor schedule and booking.</description>
    <flexiPage>HMS_Home</flexiPage>
    <label>HMS Home</label>
    <motif>Custom1: Heart</motif>
</CustomTab>`);

// ---------- app ----------
const views = [
  ['Patient__c', 'Patient_Record_Page'],
  ['Doctor__c', 'Doctor_Record_Page'],
  ['Appointment__c', 'Appointment_Record_Page']
];
const profiles = ['Admin', 'Hospital_Admin', 'Doctor_Profile', 'Receptionist_Profile'];
w('applications/MedCare_HMS.app-meta.xml', `
<CustomApplication xmlns="http://soap.sforce.com/2006/04/metadata">
${views.map(([o, p]) => `    <actionOverrides>
        <actionName>View</actionName>
        <content>${p}</content>
        <formFactor>Large</formFactor>
        <skipRecordTypeSelect>false</skipRecordTypeSelect>
        <type>Flexipage</type>
        <pageOrSobjectType>${o}</pageOrSobjectType>
    </actionOverrides>`).join('\n')}
    <brand>
        <headerColor>#621BA5</headerColor>
        <shouldOverrideOrgTheme>false</shouldOverrideOrgTheme>
    </brand>
    <description>MedCare Hospital Management System</description>
    <formFactors>Small</formFactors>
    <formFactors>Large</formFactors>
    <isNavAutoTempTabsDisabled>false</isNavAutoTempTabsDisabled>
    <isNavPersonalizationDisabled>false</isNavPersonalizationDisabled>
    <isNavTabPersistenceDisabled>false</isNavTabPersistenceDisabled>
    <label>MedCare HMS</label>
    <navType>Standard</navType>
${profiles.map((pr) => `    <profileActionOverrides>
        <actionName>View</actionName>
        <content>Patient_Emergency_Record_Page</content>
        <formFactor>Large</formFactor>
        <pageOrSobjectType>Patient__c</pageOrSobjectType>
        <recordType>Patient__c.Emergency</recordType>
        <type>Flexipage</type>
        <profile>${pr}</profile>
    </profileActionOverrides>`).join('\n')}
${['HMS_Home', 'Patient__c', 'Doctor__c', 'Appointment__c', 'Department__c', 'Billing__c', 'Medical_Record__c', 'Lab_Result__c', 'Procedure__c', 'standard-report', 'standard-Dashboard'].map((t) => `    <tabs>${t}</tabs>`).join('\n')}
    <uiType>Lightning</uiType>
</CustomApplication>`);

// ---------- path ----------
w('settings/PathAssistant.settings-meta.xml', `
<PathAssistantSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <canOverrideAutoPathCollapseWithUserPref>true</canOverrideAutoPathCollapseWithUserPref>
    <pathAssistantEnabled>true</pathAssistantEnabled>
</PathAssistantSettings>`);
const guidance = {
  Requested: ['Appointment_Date__c', 'Slot__c', 'Doctor__c', 'Call the patient to confirm the slot (see the confirmation task).'],
  Confirmed: ['Patient_Email__c', 'Appointment_Type__c', 'A confirmation email is sent automatically to the patient.'],
  Completed: ['Specialist_Required__c', 'A Billing record is created automatically with the default charge for this appointment type.'],
  Cancelled: ['Patient_Email__c', 'The doctor slot is freed and a cancellation email is sent to the patient.']
};
for (const [rt, label] of [['General_Consultation', 'General'], ['Specialist_Consultation', 'Specialist'], ['Emergency', 'Emergency']]) {
  w(`pathAssistants/Appointment_Status_${label}.pathAssistant-meta.xml`, `
<PathAssistant xmlns="http://soap.sforce.com/2006/04/metadata">
    <active>true</active>
    <entityName>Appointment__c</entityName>
    <fieldName>Status__c</fieldName>
    <masterLabel>Appointment Status - ${label}</masterLabel>
${Object.entries(guidance).map(([step, g]) => `    <pathAssistantSteps>
${g.slice(0, -1).map((f) => `        <fieldNames>${f}</fieldNames>`).join('\n')}
        <info>${x('<p>' + g[g.length - 1] + '</p>')}</info>
        <picklistValueName>${step}</picklistValueName>
    </pathAssistantSteps>`).join('\n')}
    <recordTypeName>${rt}</recordTypeName>
</PathAssistant>`);
}

// ---------- reports ----------
w('reports/HMS_Reports.reportFolder-meta.xml', `
<ReportFolder xmlns="http://soap.sforce.com/2006/04/metadata">
    <accessType>Public</accessType>
    <name>HMS Reports</name>
    <publicFolderAccess>ReadWrite</publicFolderAccess>
</ReportFolder>`);
const cols = (list) => list.map((c) => (typeof c === 'string' ? `    <columns>\n        <field>${c}</field>\n    </columns>` : `    <columns>\n        <aggregateTypes>${c.agg}</aggregateTypes>\n        <field>${c.field}</field>\n    </columns>`)).join('\n');
const grp = (tag, field, gran) => `    <${tag}>\n${gran ? `        <dateGranularity>${gran}</dateGranularity>\n` : ''}        <field>${field}</field>\n        <sortOrder>Asc</sortOrder>\n    </${tag}>`;
const filter = (items) =>
  items.length
    ? `    <filter>
${items.map(([c, op, v]) => `        <criteriaItems>\n            <column>${c}</column>\n            <columnToColumn>false</columnToColumn>\n            <isUnlocked>true</isUnlocked>\n            <operator>${op}</operator>\n            <value>${x(v)}</value>\n        </criteriaItems>`).join('\n')}
    </filter>`
    : '';
const chart = (type, groupingColumn, summaryColumn = 'RowCount') => `    <chart>
        <backgroundColor1>#FFFFFF</backgroundColor1>
        <backgroundColor2>#FFFFFF</backgroundColor2>
        <backgroundFadeDir>Diagonal</backgroundFadeDir>
        <chartSummaries>
${summaryColumn === 'RowCount' ? '            <axisBinding>y</axisBinding>\n            <column>RowCount</column>' : `            <aggregate>Sum</aggregate>\n            <axisBinding>y</axisBinding>\n            <column>${summaryColumn}</column>`}
        </chartSummaries>
        <chartType>${type}</chartType>
        <enableHoverLabels>true</enableHoverLabels>
        <expandOthers>true</expandOthers>
        <groupingColumn>${groupingColumn}</groupingColumn>
        <legendPosition>Right</legendPosition>
        <location>CHART_BOTTOM</location>
        <showAxisLabels>true</showAxisLabels>
        <showPercentage>${type === 'Pie' || type === 'Donut'}</showPercentage>
        <showTotal>${type === 'Donut'}</showTotal>
${type.includes('Stacked') ? '' : '        <showValues>true</showValues>'}
        <size>Medium</size>
        <summaryAxisRange>Auto</summaryAxisRange>
        <textColor>#000000</textColor>
        <textSize>12</textSize>
        <titleColor>#000000</titleColor>
        <titleSize>18</titleSize>
    </chart>`;
const report = (name, o) =>
  w(`reports/HMS_Reports/${name}.report-meta.xml`, `
<Report xmlns="http://soap.sforce.com/2006/04/metadata">
${o.chart || ''}
${cols(o.columns)}
    <description>${x(o.desc)}</description>
${filter(o.filters || [])}
    <format>${o.format}</format>
${(o.across || []).map(([f, g]) => grp('groupingsAcross', f, g)).join('\n')}
${(o.down || []).map(([f, g]) => grp('groupingsDown', f, g)).join('\n')}
    <name>${x(o.label)}</name>
    <params>
        <name>co</name>
        <value>1</value>
    </params>
    <reportType>${o.type}</reportType>
    <scope>organization</scope>
    <showDetails>${o.showDetails !== false}</showDetails>
    <showGrandTotal>true</showGrandTotal>
    <showSubTotals>true</showSubTotals>
${o.sortColumn ? `    <sortColumn>${o.sortColumn}</sortColumn>\n    <sortOrder>Asc</sortOrder>` : ''}
    <timeFrameFilter>
        <dateColumn>${o.dateColumn}</dateColumn>
        <interval>${o.interval}</interval>
    </timeFrameFilter>
</Report>`);

const APT = 'CustomEntity$Appointment__c';
report('Todays_Appointment_List', {
  label: "Today's Appointment List",
  desc: "Tabular: today's appointments with patient name, doctor, status and slot time.",
  type: APT,
  format: 'Tabular',
  columns: ['CUST_NAME', 'Appointment__c.Patient_Name__c', 'Appointment__c.Patient__c', 'Appointment__c.Doctor__c', 'Appointment__c.Status__c', 'Appointment__c.Slot__c'],
  sortColumn: 'Appointment__c.Slot__c',
  dateColumn: 'Appointment__c.Appointment_Date__c',
  interval: 'INTERVAL_TODAY'
});
report('Todays_Appointments_by_Status', {
  label: "Today's Appointments by Status",
  desc: "Count of today's appointments (dashboard metric).",
  type: APT,
  format: 'Summary',
  columns: ['CUST_NAME', 'Appointment__c.Doctor__c', 'Appointment__c.Slot__c'],
  down: [['Appointment__c.Status__c']],
  dateColumn: 'Appointment__c.Appointment_Date__c',
  interval: 'INTERVAL_TODAY'
});
// Billing is the detail of a master-detail, so it is reported through the Appointment -> Billing report type.
const BILLING = 'CustomEntityCustomEntity$Appointment__c$Billing__c';
report('Monthly_Revenue_by_Department', {
  label: 'Monthly Revenue by Department',
  desc: 'Summary: billing amount grouped by department and month.',
  type: BILLING,
  format: 'Summary',
  chart: chart('VerticalColumnStacked', 'CHILD_CREATED_DATE', 'Billing__c.Amount_Due__c').replace('<groupingColumn>CHILD_CREATED_DATE</groupingColumn>', '<groupingColumn>CHILD_CREATED_DATE</groupingColumn>\n        <secondaryGroupingColumn>Billing__c.Department_Name__c</secondaryGroupingColumn>'),
  columns: ['CHILD_NAME', 'Billing__c.Patient__c', { agg: 'Sum', field: 'Billing__c.Total_Charges__c' }, { agg: 'Sum', field: 'Billing__c.Insurance_Amount__c' }, { agg: 'Sum', field: 'Billing__c.Amount_Due__c' }],
  down: [['CHILD_CREATED_DATE', 'Month'], ['Billing__c.Department_Name__c']],
  dateColumn: 'CHILD_CREATED_DATE',
  interval: 'INTERVAL_CURY'
});
report('Doctor_Performance', {
  label: 'Doctor Performance',
  desc: 'Matrix: appointment count per doctor (rows) by month (columns).',
  type: APT,
  format: 'Matrix',
  columns: [],
  down: [['Appointment__c.Doctor__c']],
  across: [['Appointment__c.Appointment_Date__c', 'Month']],
  dateColumn: 'Appointment__c.Appointment_Date__c',
  interval: 'INTERVAL_CURY'
});
report('Appointment_Status_Distribution', {
  label: 'Appointment Status Distribution',
  desc: 'Pie chart of appointments by status.',
  type: APT,
  format: 'Summary',
  chart: chart('Pie', 'Appointment__c.Status__c'),
  columns: ['CUST_NAME', 'Appointment__c.Patient_Name__c', 'Appointment__c.Doctor__c', 'Appointment__c.Appointment_Date__c'],
  down: [['Appointment__c.Status__c']],
  dateColumn: 'Appointment__c.Appointment_Date__c',
  interval: 'INTERVAL_CURY'
});
report('Bed_Occupancy_by_Department', {
  label: 'Bed Occupancy by Department',
  desc: 'Occupied beds per department (dashboard donut).',
  type: 'CustomEntity$Department__c',
  format: 'Summary',
  columns: [{ agg: 'Sum', field: 'Department__c.Occupied_Beds__c' }, { agg: 'Sum', field: 'Department__c.Bed_Count__c' }, 'Department__c.Floor__c'],
  down: [['CUST_NAME']],
  dateColumn: 'CUST_CREATED_DATE',
  interval: 'INTERVAL_CUSTOM'
});
report('Pending_Bill_Approvals', {
  label: 'Pending Bill Approvals',
  desc: 'Emergency bills submitted for approval.',
  type: BILLING,
  format: 'Summary',
  columns: ['CHILD_NAME', 'Billing__c.Department_Name__c', { agg: 'Sum', field: 'Billing__c.Amount_Due__c' }],
  filters: [['Billing__c.Status__c', 'equals', 'Submitted']],
  down: [['Billing__c.Patient__c']],
  dateColumn: 'CHILD_CREATED_DATE',
  interval: 'INTERVAL_CUSTOM'
});
report('Doctor_Workload', {
  label: 'Doctor Workload',
  desc: 'Active (Requested/Confirmed) appointments per doctor.',
  type: APT,
  format: 'Summary',
  columns: ['CUST_NAME', 'Appointment__c.Appointment_Date__c', 'Appointment__c.Status__c'],
  filters: [['Appointment__c.Status__c', 'equals', 'Requested,Confirmed']],
  down: [['Appointment__c.Doctor__c']],
  dateColumn: 'Appointment__c.Appointment_Date__c',
  interval: 'INTERVAL_CUSTOM'
});

// ---------- dashboard ----------
w('dashboards/HMS_Dashboards.dashboardFolder-meta.xml', `
<DashboardFolder xmlns="http://soap.sforce.com/2006/04/metadata">
    <accessType>Public</accessType>
    <name>HMS Dashboards</name>
    <publicFolderAccess>ReadOnly</publicFolderAccess>
</DashboardFolder>`);
const tile = (col, row, colSpan, rowSpan, body) => `        <dashboardGridComponents>
            <colSpan>${colSpan}</colSpan>
            <columnIndex>${col}</columnIndex>
            <dashboardComponent>
${body}
            </dashboardComponent>
            <rowIndex>${row}</rowIndex>
            <rowSpan>${rowSpan}</rowSpan>
        </dashboardGridComponents>`;
const chartComp = (type, header, rep, extra, grouping) => `                <autoselectColumnsFromReport>false</autoselectColumnsFromReport>
                <chartAxisRange>Auto</chartAxisRange>
                <chartSummary>
${extra || '                    <axisBinding>y</axisBinding>\n                    <column>RowCount</column>'}
                </chartSummary>
                <componentType>${type}</componentType>
                <displayUnits>Auto</displayUnits>
                <drillEnabled>false</drillEnabled>
                <drillToDetailEnabled>false</drillToDetailEnabled>
                <enableHover>true</enableHover>
                <expandOthers>false</expandOthers>
                <groupingColumn>${grouping}</groupingColumn>
                <groupingSortProperties/>
                <header>${x(header)}</header>
                <legendPosition>Bottom</legendPosition>
                <report>HMS_Reports/${rep}</report>
                <showPercentage>${type === 'Donut'}</showPercentage>
                <showTotal>${type === 'Donut'}</showTotal>
                <showValues>true</showValues>
                <sortBy>RowLabelAscending</sortBy>
                <useReportChart>false</useReportChart>`;
const sumOf = (c) => `                    <aggregate>Sum</aggregate>\n                    <axisBinding>y</axisBinding>\n                    <column>${c}</column>`;
w('dashboards/HMS_Dashboards/Hospital_Admin_Dashboard.dashboard-meta.xml', `
<Dashboard xmlns="http://soap.sforce.com/2006/04/metadata">
    <backgroundEndColor>#FFFFFF</backgroundEndColor>
    <backgroundFadeDirection>Diagonal</backgroundFadeDirection>
    <backgroundStartColor>#FFFFFF</backgroundStartColor>
    <chartTheme>light</chartTheme>
    <colorPalette>unity</colorPalette>
    <dashboardChartTheme>light</dashboardChartTheme>
    <dashboardColorPalette>unity</dashboardColorPalette>
    <dashboardGridLayout>
${tile(0, 0, 4, 4, `                <autoselectColumnsFromReport>true</autoselectColumnsFromReport>
                <componentType>Metric</componentType>
                <displayUnits>Auto</displayUnits>
                <drillEnabled>false</drillEnabled>
                <drillToDetailEnabled>false</drillToDetailEnabled>
                <footer>Scheduled for today</footer>
                <groupingSortProperties/>
                <header>Today's Appointments</header>
                <indicatorBreakpoint1>10.0</indicatorBreakpoint1>
                <indicatorBreakpoint2>30.0</indicatorBreakpoint2>
                <indicatorHighColor>#54C254</indicatorHighColor>
                <indicatorLowColor>#C25454</indicatorLowColor>
                <indicatorMiddleColor>#C2C254</indicatorMiddleColor>
                <report>HMS_Reports/Todays_Appointments_by_Status</report>
                <showRange>false</showRange>`)}
${tile(4, 0, 8, 8, chartComp('Column', 'Monthly Revenue', 'Monthly_Revenue_by_Department', sumOf('Billing__c.Amount_Due__c'), 'CHILD_CREATED_DATE'))}
${tile(0, 4, 4, 8, chartComp('Donut', 'Bed Occupancy by Department', 'Bed_Occupancy_by_Department', sumOf('Department__c.Occupied_Beds__c'), 'CUST_NAME'))}
${tile(4, 8, 4, 8, `                <autoselectColumnsFromReport>true</autoselectColumnsFromReport>
                <componentType>Table</componentType>
                <displayUnits>Auto</displayUnits>
                <drillEnabled>false</drillEnabled>
                <drillToDetailEnabled>false</drillToDetailEnabled>
                <groupingSortProperties/>
                <header>Pending Approvals</header>
                <indicatorHighColor>#54C254</indicatorHighColor>
                <indicatorLowColor>#C25454</indicatorLowColor>
                <indicatorMiddleColor>#C2C254</indicatorMiddleColor>
                <report>HMS_Reports/Pending_Bill_Approvals</report>
                <showPicturesOnTables>false</showPicturesOnTables>
                <sortBy>RowValueDescending</sortBy>`)}
${tile(8, 8, 4, 8, chartComp('Bar', 'Doctor Workload', 'Doctor_Workload', '', 'Appointment__c.Doctor__c'))}
${tile(0, 12, 4, 8, chartComp('Pie', 'Appointment Status', 'Appointment_Status_Distribution', '', 'Appointment__c.Status__c'))}
        <numberOfColumns>12</numberOfColumns>
        <rowHeight>36</rowHeight>
    </dashboardGridLayout>
    <dashboardType>SpecifiedUser</dashboardType>
    <description>Hospital Admin dashboard: today's appointments, monthly revenue, bed occupancy, pending approvals, doctor workload.</description>
    <isGridLayout>true</isGridLayout>
    <runningUser>${ADMIN_USER}</runningUser>
    <textColor>#000000</textColor>
    <title>Hospital Admin Dashboard</title>
    <titleColor>#000000</titleColor>
    <titleSize>12</titleSize>
</Dashboard>`);
console.log('ok');
