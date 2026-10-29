@IsTest(SeeAllData=false)
private class PatientRestServiceTest {
    private static PatientRestService.PatientInfo callGet(String key) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/HMS/patient/' + key;
        request.httpMethod = 'GET';
        RestContext.request = request;
        RestContext.response = new RestResponse();
        return PatientRestService.getPatient();
    }

    @IsTest
    static void getByRecordIdIncludesAppointmentsAndRecords() {
        Doctor__c doctor = TestDataFactory.createDoctor();
        Patient__c patient = TestDataFactory.createPatient();
        TestDataFactory.createAppointment(doctor.Id, patient.Id, Date.today().addDays(1), '09:00 AM');
        insert new Medical_Record__c(Patient__c = patient.Id, Diagnosis__c = 'Hypertension', Prescription__c = 'Amlodipine 5mg');

        Test.startTest();
        PatientRestService.PatientInfo info = callGet(patient.Id);
        Test.stopTest();

        Assert.areEqual(200, RestContext.response.statusCode);
        Assert.areEqual(patient.Id, info.recordId);
        Assert.areEqual(patient.Full_Name__c, info.name);
        Assert.areEqual(1, info.appointments.size());
        Assert.areEqual(doctor.Name, info.appointments[0].doctor);
        Assert.areEqual('Hypertension', info.medicalRecords[0].diagnosis);
        Assert.isFalse(JSON.serialize(info).contains(patient.SSN__c), 'SSN is never exposed');
    }

    @IsTest
    static void getByPatientNumber() {
        Patient__c patient = TestDataFactory.createPatient();
        String patientNumber = [SELECT Name FROM Patient__c WHERE Id = :patient.Id].Name;

        Test.startTest();
        PatientRestService.PatientInfo info = callGet(patientNumber);
        Test.stopTest();

        Assert.areEqual(patientNumber, info.patientId);
    }

    @IsTest
    static void unknownPatientReturns404() {
        Test.startTest();
        PatientRestService.PatientInfo info = callGet('PAT-DOES-NOT-EXIST');
        Test.stopTest();

        Assert.isNull(info);
        Assert.areEqual(404, RestContext.response.statusCode);
    }

    @IsTest
    static void missingIdReturns400() {
        Test.startTest();
        PatientRestService.PatientInfo info = callGet('');
        Test.stopTest();

        Assert.isNull(info);
        Assert.areEqual(400, RestContext.response.statusCode);
    }
}
