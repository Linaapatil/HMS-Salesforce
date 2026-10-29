@IsTest(SeeAllData=false)
private class LabIntegrationServiceTest {
    @IsTest
    static void getLabResultsReturnsBody() {
        Test.setMock(HttpCalloutMock.class, new LabSystemCalloutMock());
        Id patientId = TestDataFactory.createPatient().Id;

        Test.startTest();
        String result = LabIntegrationService.getLabResults(patientId);
        Test.stopTest();

        Assert.isTrue(result.contains('Blood Test'));
        Assert.isTrue(result.contains('Normal'));
    }

    @IsTest
    static void nullPatientIdRejected() {
        Test.startTest();
        try {
            LabIntegrationService.getLabResults(null);
            Assert.fail('Expected exception.');
        } catch (HospitalException e) {
            Assert.areEqual('Patient ID is required.', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void apiErrorRaisesHospitalException() {
        Test.setMock(HttpCalloutMock.class, new LabSystemCalloutMock(500));
        Id patientId = TestDataFactory.createPatient().Id;

        Test.startTest();
        try {
            LabIntegrationService.getLabResults(patientId);
            Assert.fail('Expected exception.');
        } catch (HospitalException e) {
            Assert.areEqual('Lab API error: 500', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void importStoresAndProcessesResults() {
        Test.setMock(HttpCalloutMock.class, new LabSystemCalloutMock());
        Id patientId = TestDataFactory.createPatient().Id;

        Test.startTest();
        Integer imported = LabIntegrationService.importLabResults(patientId);
        Test.stopTest();

        Assert.areEqual(2, imported);
        List<Lab_Result__c> results = [SELECT Test_Name__c, Status__c, Result_Date__c FROM Lab_Result__c WHERE Patient__c = :patientId ORDER BY Test_Name__c];
        Assert.areEqual(2, results.size());
        Assert.areEqual('Completed', results[0].Status__c, 'Queueable processed the imported results');
        Assert.areEqual(Date.newInstance(2026, 1, 15), results[0].Result_Date__c);
        Assert.areEqual(Date.today(), results[1].Result_Date__c, 'Missing dates default to today');
    }

    @IsTest
    static void importSurfacesApiErrorsToLwc() {
        Test.setMock(HttpCalloutMock.class, new LabSystemCalloutMock(503));
        Id patientId = TestDataFactory.createPatient().Id;

        Test.startTest();
        try {
            LabIntegrationService.importLabResults(patientId);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        Test.stopTest();
    }
}
