/**
 * REST integration with the external lab system.
 * GET callout:LabSystem_NC/results/{patientId}  ->  {"patientId": "...", "results": [{"test": "...", "result": "...", "date": "yyyy-mm-dd"}]}
 */
public with sharing class LabIntegrationService {
    public static final String ENDPOINT = 'callout:LabSystem_NC/results/';

    /** Raw JSON body from the lab API. */
    public static String getLabResults(Id patientId) {
        if (patientId == null) {
            throw new HospitalException('Patient ID is required.');
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT + patientId);
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(10000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            throw new HospitalException('Lab API error: ' + response.getStatusCode());
        }
        return response.getBody();
    }

    /** Parsed lab results for a patient. */
    public static List<LabResult> fetchLabResults(Id patientId) {
        LabResponse parsed = (LabResponse) JSON.deserialize(getLabResults(patientId), LabResponse.class);
        return parsed == null || parsed.results == null ? new List<LabResult>() : parsed.results;
    }

    /**
     * Fetches results from the lab system and stores them as Lab_Result__c records (status Pending),
     * then hands them to the LabResultProcessor queueable. Callable from LWC / quick actions.
     */
    @AuraEnabled
    public static Integer importLabResults(Id patientId) {
        try {
            List<Lab_Result__c> records = new List<Lab_Result__c>();
            for (LabResult result : fetchLabResults(patientId)) {
                records.add(
                    new Lab_Result__c(
                        Patient__c = patientId,
                        Test_Name__c = result.test,
                        Result__c = result.result,
                        Result_Date__c = String.isBlank(result.resultDate) ? Date.today() : Date.valueOf(result.resultDate),
                        Status__c = 'Pending'
                    )
                );
            }
            insert records;

            if (!records.isEmpty()) {
                List<Id> ids = new List<Id>(new Map<Id, Lab_Result__c>(records).keySet());
                System.enqueueJob(new LabResultProcessor(ids));
            }
            return records.size();
        } catch (HospitalException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class LabResponse {
        public String patientId;
        public List<LabResult> results;
    }

    public class LabResult {
        public String test;
        public String result;
        public String resultDate;
    }
}
