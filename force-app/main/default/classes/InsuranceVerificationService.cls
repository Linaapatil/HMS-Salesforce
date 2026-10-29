/**
 * SOAP integration: verifies a patient's insurance coverage against the insurance provider's
 * web service (see staticresources/InsuranceVerificationWSDL for the contract).
 *
 * The InsurancePort inner class has the same shape WSDL2Apex generates, so it can be
 * regenerated from the provider's real WSDL without touching callers.
 */
public with sharing class InsuranceVerificationService {
    public static final String NAMESPACE = 'http://medcare.example/insurance';
    public static final String ENDPOINT = 'callout:Insurance_NC/soap/verification';

    /** Verifies coverage for one patient and returns the result. */
    @AuraEnabled
    public static CoverageResult verifyPatientCoverage(Id patientId) {
        Patient__c patient = [
            SELECT Id, Insurance_Provider__c, Insurance_Policy_No__c
            FROM Patient__c
            WHERE Id = :patientId
            WITH USER_MODE
            LIMIT 1
        ];

        if (String.isBlank(patient.Insurance_Policy_No__c)) {
            throw new AuraHandledException('Patient has no insurance policy number.');
        }

        VerifyCoverageResponse response = new InsurancePort().verifyCoverage(patient.Insurance_Provider__c, patient.Insurance_Policy_No__c);

        CoverageResult result = new CoverageResult();
        result.covered = response.covered == true;
        result.coveragePercent = response.coveragePercent == null ? 0 : response.coveragePercent;
        result.message = response.message;
        return result;
    }

    public class CoverageResult {
        @AuraEnabled
        public Boolean covered;
        @AuraEnabled
        public Decimal coveragePercent;
        @AuraEnabled
        public String message;
    }

    // ---- WSDL2Apex-style stub ----------------------------------------------------------------

    public class VerifyCoverageRequest {
        public String provider;
        public String policyNumber;
        private String[] provider_type_info = new List<String>{ 'provider', NAMESPACE, null, '0', '1', 'false' };
        private String[] policyNumber_type_info = new List<String>{ 'policyNumber', NAMESPACE, null, '1', '1', 'false' };
        private String[] apex_schema_type_info = new List<String>{ NAMESPACE, 'true', 'false' };
        private String[] field_order_type_info = new List<String>{ 'provider', 'policyNumber' };
    }

    public class VerifyCoverageResponse {
        public Boolean covered;
        public Decimal coveragePercent;
        public String message;
        private String[] covered_type_info = new List<String>{ 'covered', NAMESPACE, null, '1', '1', 'false' };
        private String[] coveragePercent_type_info = new List<String>{ 'coveragePercent', NAMESPACE, null, '0', '1', 'false' };
        private String[] message_type_info = new List<String>{ 'message', NAMESPACE, null, '0', '1', 'false' };
        private String[] apex_schema_type_info = new List<String>{ NAMESPACE, 'true', 'false' };
        private String[] field_order_type_info = new List<String>{ 'covered', 'coveragePercent', 'message' };
    }

    public class InsurancePort {
        public String endpoint_x = ENDPOINT;
        public Map<String, String> inputHttpHeaders_x;
        public Integer timeout_x = 10000;
        private String[] ns_map_type_info = new List<String>{ NAMESPACE, 'InsuranceVerificationService' };

        public VerifyCoverageResponse verifyCoverage(String provider, String policyNumber) {
            VerifyCoverageRequest request_x = new VerifyCoverageRequest();
            request_x.provider = provider;
            request_x.policyNumber = policyNumber;

            Map<String, VerifyCoverageResponse> response_map_x = new Map<String, VerifyCoverageResponse>();
            response_map_x.put('response_x', null);
            WebServiceCallout.invoke(
                this,
                request_x,
                response_map_x,
                new List<String>{
                    endpoint_x,
                    NAMESPACE + '/verifyCoverage',
                    NAMESPACE,
                    'verifyCoverageRequest',
                    NAMESPACE,
                    'verifyCoverageResponse',
                    'InsuranceVerificationService.VerifyCoverageResponse'
                }
            );
            return response_map_x.get('response_x');
        }
    }
}
