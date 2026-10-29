@IsTest(SeeAllData=false)
private class PatientServiceTest {
    @IsTest
    static void ageGroups() {
        Test.startTest();
        Assert.areEqual('Unknown', PatientService.calculateAgeGroup((Integer) null));
        Assert.areEqual('Unknown', PatientService.calculateAgeGroup(-1));
        Assert.areEqual('Child', PatientService.calculateAgeGroup(12));
        Assert.areEqual('Teen', PatientService.calculateAgeGroup(13));
        Assert.areEqual('Teen', PatientService.calculateAgeGroup(19));
        Assert.areEqual('Adult', PatientService.calculateAgeGroup(20));
        Assert.areEqual('Adult', PatientService.calculateAgeGroup(59));
        Assert.areEqual('Senior', PatientService.calculateAgeGroup(60));
        Test.stopTest();
    }

    @IsTest
    static void ageFromDateOfBirth() {
        Date today = Date.today();

        Test.startTest();
        Assert.areEqual(30, PatientService.calculateAge(today.addYears(-30)));
        Assert.areEqual(29, PatientService.calculateAge(today.addYears(-30).addDays(1)), 'Birthday not reached yet');
        Assert.isNull(PatientService.calculateAge(today.addDays(1)));
        Assert.isNull(PatientService.calculateAge(null));
        Assert.areEqual('Senior', PatientService.calculateAgeGroup(today.addYears(-70)));
        Test.stopTest();
    }

    @IsTest
    static void mergeDuplicatesReparentsChildrenAndDeletesCopies() {
        Doctor__c doctor = TestDataFactory.createDoctor();
        List<Patient__c> patients = TestDataFactory.createPatients(3);
        // patients[0] and [1] are the same person; [2] is unrelated.
        patients[1].SSN__c = patients[0].SSN__c;
        update patients[1];

        Appointment__c appointment = TestDataFactory.createAppointment(doctor.Id, patients[1].Id, Date.today().addDays(1), '09:00 AM');
        Billing__c bill = TestDataFactory.createBilling(patients[1].Id, TestDataFactory.createProcedure(100).Id, appointment.Id);
        Lab_Result__c lab = TestDataFactory.buildLabResult(patients[1].Id, 'Normal');
        insert lab;

        Test.startTest();
        Integer removed = PatientService.mergeDuplicates(new List<Patient__c>{ patients[0], patients[2] });
        Test.stopTest();

        Assert.areEqual(1, removed);
        Assert.areEqual(2, [SELECT COUNT() FROM Patient__c]);
        Assert.areEqual(patients[0].Id, [SELECT Patient__c FROM Appointment__c WHERE Id = :appointment.Id].Patient__c);
        Assert.areEqual(patients[0].Id, [SELECT Patient__c FROM Billing__c WHERE Id = :bill.Id].Patient__c);
        Assert.areEqual(patients[0].Id, [SELECT Patient__c FROM Lab_Result__c WHERE Id = :lab.Id].Patient__c);
    }

    @IsTest
    static void mergeWithoutDuplicatesDoesNothing() {
        List<Patient__c> patients = TestDataFactory.createPatients(2);
        Patient__c noSsn = new Patient__c(Full_Name__c = 'No SSN');

        Test.startTest();
        Integer removed = PatientService.mergeDuplicates(patients);
        Integer removedEmpty = PatientService.mergeDuplicates(new List<Patient__c>{ noSsn });
        Test.stopTest();

        Assert.areEqual(0, removed);
        Assert.areEqual(0, removedEmpty);
        Assert.areEqual(2, [SELECT COUNT() FROM Patient__c]);
    }

    @IsTest
    static void searchByNamePatientIdAndRecordId() {
        Patient__c patient = TestDataFactory.buildPatient();
        patient.Full_Name__c = 'Ananya Sharma';
        insert patient;
        TestDataFactory.createPatient();
        patient = [SELECT Id, Name FROM Patient__c WHERE Id = :patient.Id];

        Test.startTest();
        List<Patient__c> byName = PatientService.searchPatients('ananya');
        List<Patient__c> byPatientId = PatientService.searchPatients(patient.Name);
        List<Patient__c> byRecordId = PatientService.searchPatients(String.valueOf(patient.Id));
        List<Patient__c> blank = PatientService.searchPatients('  ');
        List<Patient__c> tooShort = PatientService.searchPatients('a');
        List<Patient__c> noMatch = PatientService.searchPatients('zzzzzz');
        Test.stopTest();

        Assert.areEqual(1, byName.size());
        Assert.areEqual(patient.Id, byName[0].Id);
        Assert.areEqual(patient.Id, byPatientId[0].Id);
        Assert.areEqual(1, byRecordId.size());
        Assert.isTrue(blank.isEmpty());
        Assert.isTrue(tooShort.isEmpty());
        Assert.isTrue(noMatch.isEmpty());
    }

    @IsTest
    static void futureDateOfBirthBlockedByValidationRule() {
        Patient__c patient = TestDataFactory.buildPatient();
        patient.DOB__c = Date.today().addDays(10);

        Test.startTest();
        Database.SaveResult result = Database.insert(patient, false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
        Assert.areEqual('Date of Birth cannot be a future date.', result.getErrors()[0].getMessage());
    }
}
