/**
 * Generic HttpCalloutMock for HMS integrations. Records every request it receives.
 */
@IsTest
public class HmsHttpCalloutMock implements HttpCalloutMock {
    public static List<HttpRequest> requests = new List<HttpRequest>();

    private final Integer statusCode;
    private final String body;

    public HmsHttpCalloutMock(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
        requests.add(request);
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setHeader('Content-Type', 'application/json');
        response.setBody(body);
        return response;
    }
}
