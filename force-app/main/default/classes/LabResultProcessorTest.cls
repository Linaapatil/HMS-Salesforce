@IsTest(SeeAllData=false)
private class LabResultProcessorTest {
    @IsTest
    static void processesPendingResults() {
        Patient__c patient = TestDataFactory.createPatient();
        List<Lab_Result__c> results = new List<Lab_Result__c>{
            TestDataFactory.buildLabResult(patient.Id, 'Normal'),
            TestDataFactory.buildLabResult(patient.Id, null)
        };
        Lab_Result__c alreadyDone = TestDataFactory.buildLabResult(patient.Id, 'Old');
        alreadyDone.Status__c = 'Completed';
        alreadyDone.Result_Date__c = Date.today().addDays(-5);
        results.add(alreadyDone);
        insert results;

        Test.startTest();
        System.enqueueJob(new LabResultProcessor(new List<Id>{ results[0].Id, results[1].Id, results[2].Id }));
        Test.stopTest();

        Map<Id, Lab_Result__c> saved = new Map<Id, Lab_Result__c>([SELECT Status__c, Result_Date__c FROM Lab_Result__c]);
        Assert.areEqual('Completed', saved.get(results[0].Id).Status__c);
        Assert.areEqual('Failed', saved.get(results[1].Id).Status__c, 'No result value from the lab');
        Assert.areEqual(Date.today().addDays(-5), saved.get(results[2].Id).Result_Date__c, 'Completed results are untouched');
    }

    @IsTest
    static void chainsWhenMoreThanOneChunk() {
        Patient__c patient = TestDataFactory.createPatient();
        List<Lab_Result__c> results = new List<Lab_Result__c>();
        for (Integer i = 0; i < LabResultProcessor.CHUNK_SIZE + 5; i++) {
            results.add(TestDataFactory.buildLabResult(patient.Id, 'Normal'));
        }
        insert results;

        Test.startTest();
        System.enqueueJob(new LabResultProcessor(new List<Id>(new Map<Id, Lab_Result__c>(results).keySet())));
        Test.stopTest();

        Assert.areEqual(1, LabResultProcessor.chainedJobs, 'Remaining records are chained to a new job');
        Assert.areEqual(LabResultProcessor.CHUNK_SIZE, [SELECT COUNT() FROM Lab_Result__c WHERE Status__c = 'Completed']);
    }

    @IsTest
    static void emptyInputIsNoOp() {
        Test.startTest();
        System.enqueueJob(new LabResultProcessor(null));
        Test.stopTest();

        Assert.areEqual(0, LabResultProcessor.chainedJobs);
    }
}
