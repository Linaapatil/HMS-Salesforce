/**
 * HttpCalloutMock for the external lab system (LabSystem_NC).
 */
@IsTest
public class LabSystemCalloutMock implements HttpCalloutMock {
    public static final String SUCCESS_BODY =
        '{"patientId":"001TEST","results":[' +
        '{"test":"Blood Test","result":"Normal","resultDate":"2026-01-15"},' +
        '{"test":"Lipid Profile","result":"LDL slightly high"}]}';

    private final Integer statusCode;

    public LabSystemCalloutMock() {
        this(200);
    }

    public LabSystemCalloutMock(Integer statusCode) {
        this.statusCode = statusCode;
    }

    public HttpResponse respond(HttpRequest request) {
        Assert.areEqual('GET', request.getMethod());
        Assert.isTrue(request.getEndpoint().startsWith(LabIntegrationService.ENDPOINT));

        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setHeader('Content-Type', 'application/json');
        response.setBody(statusCode == 200 ? SUCCESS_BODY : '{"error":"unavailable"}');
        return response;
    }
}
