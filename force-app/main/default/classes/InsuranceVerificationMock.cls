/**
 * WebServiceMock for the SOAP insurance verification service.
 */
@IsTest
public class InsuranceVerificationMock implements WebServiceMock {
    private final Boolean covered;
    private final Decimal coveragePercent;

    public InsuranceVerificationMock(Boolean covered, Decimal coveragePercent) {
        this.covered = covered;
        this.coveragePercent = coveragePercent;
    }

    public void doInvoke(
        Object stub,
        Object request,
        Map<String, Object> response,
        String endpoint,
        String soapAction,
        String requestName,
        String responseNS,
        String responseName,
        String responseType
    ) {
        InsuranceVerificationService.VerifyCoverageRequest verifyRequest = (InsuranceVerificationService.VerifyCoverageRequest) request;
        InsuranceVerificationService.VerifyCoverageResponse verifyResponse = new InsuranceVerificationService.VerifyCoverageResponse();
        verifyResponse.covered = covered;
        verifyResponse.coveragePercent = coveragePercent;
        verifyResponse.message = (covered ? 'Policy active: ' : 'Policy not found: ') + verifyRequest.policyNumber;
        response.put('response_x', verifyResponse);
    }
}
