/**
 * Queueable Apex: processes lab results in chunks and chains itself for the remainder,
 * so any number of records can be handled without hitting per-transaction governor limits.
 *
 * Pending results are marked Processing, then Completed once they have a result value,
 * or Failed when the lab returned nothing.
 */
public with sharing class LabResultProcessor implements Queueable {
    public static final Integer CHUNK_SIZE = 100;

    private final List<Id> labResultIds;

    public LabResultProcessor(List<Id> labResultIds) {
        this.labResultIds = labResultIds == null ? new List<Id>() : labResultIds;
    }

    public void execute(QueueableContext context) {
        List<Id> current = new List<Id>();
        List<Id> remaining = new List<Id>();

        for (Integer i = 0; i < labResultIds.size(); i++) {
            if (i < CHUNK_SIZE) {
                current.add(labResultIds[i]);
            } else {
                remaining.add(labResultIds[i]);
            }
        }

        processChunk(current);

        if (!remaining.isEmpty()) {
            chain(remaining);
        }
    }

    @TestVisible
    private static void processChunk(List<Id> ids) {
        List<Lab_Result__c> updates = new List<Lab_Result__c>();

        for (Lab_Result__c result : [SELECT Id, Status__c, Result__c, Result_Date__c FROM Lab_Result__c WHERE Id IN :ids]) {
            if (result.Status__c != 'Pending' && result.Status__c != 'Processing') {
                continue;
            }
            result.Status__c = String.isBlank(result.Result__c) ? 'Failed' : 'Completed';
            if (result.Result_Date__c == null) {
                result.Result_Date__c = Date.today();
            }
            updates.add(result);
        }

        update updates;
    }

    @TestVisible
    private static Integer chainedJobs = 0;

    private static void chain(List<Id> remaining) {
        chainedJobs++;
        // Tests may only run one queueable per transaction, so chaining is skipped there.
        if (!Test.isRunningTest()) {
            System.enqueueJob(new LabResultProcessor(remaining));
        }
    }
}
