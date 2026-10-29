// Seeds MedCare HMS demo data (departments, doctors, patients, procedures, appointments,
// billing, medical records, lab results and one bill in the approval process).
// Run with:  sf apex run -o MedCare -f scripts/apex/seedData.apex
// Safe to re-run: it stops if the demo departments already exist.

if ([SELECT COUNT() FROM Department__c WHERE Name = 'Cardiology'] > 0) {
    System.debug('Demo data already present - nothing to do.');
    return;
}

Date today = Date.today();

// ---- Departments ----
Map<String, Department__c> departments = new Map<String, Department__c>{
    'Cardiology' => new Department__c(Name = 'Cardiology', Floor__c = 3, Bed_Count__c = 60, Occupied_Beds__c = 48),
    'Neurology' => new Department__c(Name = 'Neurology', Floor__c = 4, Bed_Count__c = 40, Occupied_Beds__c = 22),
    'Orthopedics' => new Department__c(Name = 'Orthopedics', Floor__c = 2, Bed_Count__c = 50, Occupied_Beds__c = 35),
    'Pediatrics' => new Department__c(Name = 'Pediatrics', Floor__c = 1, Bed_Count__c = 45, Occupied_Beds__c = 18),
    'General Medicine' => new Department__c(Name = 'General Medicine', Floor__c = 1, Bed_Count__c = 80, Occupied_Beds__c = 61),
    'Emergency Medicine' => new Department__c(Name = 'Emergency Medicine', Floor__c = 0, Bed_Count__c = 30, Occupied_Beds__c = 26)
};
insert departments.values();

// ---- Doctors (senior consultants first, then juniors reporting to them) ----
List<Doctor__c> seniors = new List<Doctor__c>{
    new Doctor__c(Name = 'Dr. Meera Iyer', License_No__c = 'MCI-100101', Specialization__c = 'Cardiology', Department__c = departments.get('Cardiology').Id, Email__c = 'meera.iyer@medcare.example'),
    new Doctor__c(Name = 'Dr. Rajesh Nair', License_No__c = 'MCI-100102', Specialization__c = 'Neurology', Department__c = departments.get('Neurology').Id, Email__c = 'rajesh.nair@medcare.example'),
    new Doctor__c(Name = 'Dr. Sunita Rao', License_No__c = 'MCI-100103', Specialization__c = 'Orthopedics', Department__c = departments.get('Orthopedics').Id, Email__c = 'sunita.rao@medcare.example'),
    new Doctor__c(Name = 'Dr. Anil Kapoor', License_No__c = 'MCI-100104', Specialization__c = 'Pediatrics', Department__c = departments.get('Pediatrics').Id, Email__c = 'anil.kapoor@medcare.example'),
    new Doctor__c(Name = 'Dr. Farah Khan', License_No__c = 'MCI-100105', Specialization__c = 'General Medicine', Department__c = departments.get('General Medicine').Id, Email__c = 'farah.khan@medcare.example', User__c = UserInfo.getUserId()),
    new Doctor__c(Name = 'Dr. Vikram Singh', License_No__c = 'MCI-100106', Specialization__c = 'Emergency Medicine', Department__c = departments.get('Emergency Medicine').Id, Email__c = 'vikram.singh@medcare.example')
};
for (Doctor__c d : seniors) {
    d.Status__c = 'Active';
    d.Availability__c = 'Available';
}
insert seniors;

List<Doctor__c> juniors = new List<Doctor__c>{
    new Doctor__c(Name = 'Dr. Kavya Menon', License_No__c = 'MCI-100201', Specialization__c = 'Cardiology', Department__c = departments.get('Cardiology').Id, Manager__c = seniors[0].Id, Status__c = 'Active', Availability__c = 'Available'),
    new Doctor__c(Name = 'Dr. Rohan Das', License_No__c = 'MCI-100202', Specialization__c = 'General Medicine', Department__c = departments.get('General Medicine').Id, Manager__c = seniors[4].Id, Status__c = 'Active', Availability__c = 'Available'),
    new Doctor__c(Name = 'Dr. Neha Joshi', License_No__c = 'MCI-100203', Specialization__c = 'Neurology', Department__c = departments.get('Neurology').Id, Manager__c = seniors[1].Id, Status__c = 'On Leave', Availability__c = 'On Leave')
};
insert juniors;

// Heads of department
List<Department__c> hodUpdates = new List<Department__c>();
for (Integer i = 0; i < seniors.size(); i++) {
    hodUpdates.add(new Department__c(Id = seniors[i].Department__c, HOD__c = seniors[i].Id));
}
update hodUpdates;

// ---- Procedures ----
List<Procedure__c> procedures = new List<Procedure__c>{
    new Procedure__c(Name = 'ECG', Procedure_Code__c = 'CAR-ECG', Price__c = 1200, Description__c = 'Electrocardiogram'),
    new Procedure__c(Name = 'Angioplasty', Procedure_Code__c = 'CAR-ANG', Price__c = 250000, Description__c = 'Coronary angioplasty with stent'),
    new Procedure__c(Name = 'MRI Brain', Procedure_Code__c = 'NEU-MRI', Price__c = 9500, Description__c = 'MRI scan of the brain'),
    new Procedure__c(Name = 'Knee Replacement', Procedure_Code__c = 'ORT-TKR', Price__c = 650000, Description__c = 'Total knee replacement'),
    new Procedure__c(Name = 'X-Ray', Procedure_Code__c = 'GEN-XRY', Price__c = 800, Description__c = 'Digital X-ray'),
    new Procedure__c(Name = 'Complete Blood Count', Procedure_Code__c = 'LAB-CBC', Price__c = 450, Description__c = 'CBC blood test')
};
insert procedures;

// ---- Patients ----
Map<String, Id> patientRt = new Map<String, Id>();
for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = 'Patient__c']) {
    patientRt.put(rt.DeveloperName, rt.Id);
}
List<String> names = new List<String>{
    'Ananya Sharma', 'Arjun Mehta', 'Priya Patel', 'Rahul Verma', 'Sneha Reddy', 'Karan Malhotra',
    'Ishita Gupta', 'Aditya Kulkarni', 'Pooja Nair', 'Siddharth Jain', 'Diya Banerjee', 'Manish Tiwari'
};
List<String> bloodGroups = new List<String>{ 'O+', 'B+', 'A+', 'AB+', 'O-', 'A-', 'B-', 'O+', 'A+', 'B+', 'O+', 'AB-' };
List<String> deptByPatient = new List<String>{
    'Cardiology', 'Cardiology', 'Neurology', 'Orthopedics', 'Pediatrics', 'General Medicine',
    'General Medicine', 'Orthopedics', 'Cardiology', 'Emergency Medicine', 'Pediatrics', 'Emergency Medicine'
};
List<Patient__c> patients = new List<Patient__c>();
for (Integer i = 0; i < names.size(); i++) {
    String dept = deptByPatient[i];
    String rtName = dept == 'Emergency Medicine' ? 'Emergency' : (Math.mod(i, 3) == 0 ? 'Inpatient' : 'Outpatient');
    patients.add(
        new Patient__c(
            RecordTypeId = patientRt.get(rtName),
            Full_Name__c = names[i],
            DOB__c = today.addYears(-(8 + i * 6)).addDays(-i * 37),
            Blood_Group__c = bloodGroups[i],
            Primary_Department__c = dept,
            Phone__c = '+91 98' + String.valueOf(10000000 + i * 734521).left(8),
            Email__c = names[i].toLowerCase().replace(' ', '.') + '@example.com',
            Address__c = (12 + i) + ' MG Road, Pune',
            Emergency_Contact_Name__c = 'Family of ' + names[i].substringBefore(' '),
            Emergency_Contact__c = '+91 97' + String.valueOf(20000000 + i * 51231).left(8),
            SSN__c = 'AADH-' + String.valueOf(4000 + i) + '-' + String.valueOf(8000 + i * 7),
            Insurance_Provider__c = Math.mod(i, 2) == 0 ? 'Star Health' : 'HDFC Ergo',
            Insurance_Policy_No__c = 'POL-' + String.valueOf(77000 + i)
        )
    );
}
insert patients;

// ---- Appointments: today, tomorrow and the next few days ----
Map<String, Id> aptRt = new Map<String, Id>();
for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = 'Appointment__c']) {
    aptRt.put(rt.DeveloperName, rt.Id);
}
List<String> slots = new List<String>{ '09:00 AM', '10:00 AM', '11:00 AM', '12:00 PM', '02:00 PM', '03:00 PM', '04:00 PM', '05:00 PM' };
List<Doctor__c> bookable = new List<Doctor__c>{ seniors[0], seniors[1], seniors[2], seniors[3], seniors[4], seniors[5], juniors[0], juniors[1] };
List<Appointment__c> appointments = new List<Appointment__c>();
for (Integer day = 0; day < 4; day++) {
    for (Integer i = 0; i < patients.size(); i++) {
        if (day > 0 && Math.mod(i + day, 2) == 0) {
            continue;
        }
        Doctor__c doc = bookable[Math.mod(i + day, bookable.size())];
        String type = doc.Specialization__c == 'Emergency Medicine' ? 'Emergency' : (Math.mod(i, 3) == 1 ? 'Specialist Consultation' : 'General Consultation');
        String rt = type == 'Emergency' ? 'Emergency' : (type == 'Specialist Consultation' ? 'Specialist_Consultation' : 'General_Consultation');
        appointments.add(
            new Appointment__c(
                RecordTypeId = aptRt.get(rt),
                Patient__c = patients[i].Id,
                Doctor__c = doc.Id,
                Appointment_Date__c = today.addDays(day),
                // i and i+8 share a doctor, so shift their slot by one to avoid a double booking.
                Slot__c = slots[Math.mod(i + day * 3 + i / bookable.size(), slots.size())],
                Appointment_Type__c = type,
                Specialist_Required__c = type == 'General Consultation' ? 'No' : 'Yes',
                Status__c = 'Requested'
            )
        );
    }
}
insert appointments;

// Move today's appointments through the lifecycle: confirmed, completed (creates billing), cancelled.
List<Appointment__c> statusUpdates = new List<Appointment__c>();
Integer n = 0;
for (Appointment__c a : appointments) {
    if (a.Appointment_Date__c != today) {
        if (Math.mod(n++, 3) == 0) {
            statusUpdates.add(new Appointment__c(Id = a.Id, Status__c = 'Confirmed'));
        }
        continue;
    }
    Integer k = statusUpdates.size();
    String status = Math.mod(k, 4) == 0 ? 'Completed' : Math.mod(k, 4) == 1 ? 'Confirmed' : Math.mod(k, 4) == 2 ? 'Completed' : 'Requested';
    if (a.Patient__c == patients[11].Id) {
        status = 'Cancelled';
    }
    statusUpdates.add(new Appointment__c(Id = a.Id, Status__c = status));
}
update statusUpdates;

// ---- Procedure-based bills (BillingTrigger prices them) ----
List<Billing__c> bills = new List<Billing__c>{
    new Billing__c(Appointment__c = appointments[0].Id, Procedure__c = procedures[1].Id, Discount__c = 5, Insurance_Coverage__c = 40, Insurance__c = true, Status__c = 'Pending'),
    new Billing__c(Appointment__c = appointments[3].Id, Procedure__c = procedures[3].Id, Discount__c = 0, Insurance_Coverage__c = 10, Insurance__c = true, Status__c = 'Pending'),
    new Billing__c(Appointment__c = appointments[2].Id, Procedure__c = procedures[2].Id, Discount__c = 10, Insurance_Coverage__c = 0, Status__c = 'Paid'),
    new Billing__c(Appointment__c = appointments[5].Id, Procedure__c = procedures[4].Id, Status__c = 'Paid')
};
insert bills;

// Submit the high-value bills into the Emergency Billing Approval process.
for (Billing__c bill : [SELECT Id, Amount_Due__c FROM Billing__c WHERE Id IN :bills AND Amount_Due__c > 100000]) {
    Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
    request.setObjectId(bill.Id);
    request.setComments('Emergency procedure bill above Rs. 1,00,000');
    request.setNextApproverIds(new List<Id>{ UserInfo.getUserId() });
    Approval.process(request);
}

// ---- Medical records & lab results ----
List<Medical_Record__c> records = new List<Medical_Record__c>();
List<Lab_Result__c> labs = new List<Lab_Result__c>();
List<String> diagnoses = new List<String>{ 'Hypertension', 'Stable angina', 'Migraine', 'Osteoarthritis (knee)', 'Viral fever', 'Type 2 diabetes' };
for (Integer i = 0; i < 6; i++) {
    records.add(
        new Medical_Record__c(
            Patient__c = patients[i].Id,
            Diagnosis__c = diagnoses[i],
            Prescription__c = 'Follow-up in 2 weeks. Medication as advised.',
            Report_URL__c = 'https://reports.medcare.example/' + patients[i].Id
        )
    );
    labs.add(new Lab_Result__c(Patient__c = patients[i].Id, Test_Name__c = 'Complete Blood Count', Result__c = Math.mod(i, 2) == 0 ? 'Normal' : null, Status__c = 'Pending', Result_Date__c = today));
}
insert records;
insert labs;
System.enqueueJob(new LabResultProcessor(new List<Id>(new Map<Id, Lab_Result__c>(labs).keySet())));

System.debug('Seeded ' + patients.size() + ' patients, ' + (seniors.size() + juniors.size()) + ' doctors, ' + appointments.size() + ' appointments.');
