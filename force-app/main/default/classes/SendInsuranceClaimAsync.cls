/**
 * Future method: asynchronous callout to the insurance provider API to submit a claim
 * for approved, insured bills. Endpoint comes from the Insurance_NC named credential.
 */
public with sharing class SendInsuranceClaimAsync {
    public static final String ENDPOINT = 'callout:Insurance_NC/claims';

    /** Safe to call from triggers: skips when there is nothing to send or we are already async. */
    public static void submitClaims(Set<Id> billingIds) {
        if (billingIds == null || billingIds.isEmpty() || System.isFuture() || System.isBatch() || System.isQueueable()) {
            return;
        }
        sendClaims(new List<Id>(billingIds));
    }

    @future(callout=true)
    public static void sendClaim(Id billingId) {
        processClaims(new List<Id>{ billingId });
    }

    @future(callout=true)
    public static void sendClaims(List<Id> billingIds) {
        processClaims(billingIds);
    }

    @TestVisible
    private static void processClaims(List<Id> billingIds) {
        List<Billing__c> bills = [
            SELECT Id, Name, Amount_Due__c, Insurance_Amount__c, Patient__r.Insurance_Provider__c, Patient__r.Insurance_Policy_No__c
            FROM Billing__c
            WHERE Id IN :billingIds
        ];

        for (Billing__c bill : bills) {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(ENDPOINT);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(10000);
            request.setBody(
                JSON.serialize(
                    new Map<String, Object>{
                        'billingId' => bill.Id,
                        'billNumber' => bill.Name,
                        'provider' => bill.Patient__r.Insurance_Provider__c,
                        'policyNumber' => bill.Patient__r.Insurance_Policy_No__c,
                        'amountDue' => bill.Amount_Due__c,
                        'insuranceAmount' => bill.Insurance_Amount__c
                    }
                )
            );

            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() >= 300) {
                System.debug(LoggingLevel.ERROR, 'Insurance claim failed for ' + bill.Name + ': ' + response.getStatusCode());
            }
        }
    }
}
