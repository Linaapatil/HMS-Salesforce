/**
 * Reusable service for sending (optionally templated) emails to patients and doctors.
 * Sending is best-effort: an org with email deliverability switched off must never
 * roll back the business transaction that triggered the email.
 */
public with sharing class EmailService {
    public static final String TEMPLATE_CANCELLATION = 'Appointment_Cancellation_Template';
    public static final String TEMPLATE_REMINDER = 'Appointment_Reminder_Template';

    @TestVisible
    private static Integer emailsQueued = 0;

    public static void sendCancellationEmails(List<Appointment__c> appointments) {
        sendAppointmentEmails(
            appointments,
            TEMPLATE_CANCELLATION,
            'Your MedCare appointment has been cancelled',
            'Your appointment on {date} at {slot} has been cancelled. Please contact MedCare Hospital to reschedule.'
        );
    }

    public static void sendReminderEmails(List<Appointment__c> appointments) {
        sendAppointmentEmails(
            appointments,
            TEMPLATE_REMINDER,
            'Reminder: your MedCare appointment is tomorrow',
            'This is a reminder that you have an appointment on {date} at {slot}.'
        );
    }

    /** Emails the patient on each appointment, rendering the named template or falling back to plain text. */
    public static void sendAppointmentEmails(
        List<Appointment__c> appointments,
        String templateDeveloperName,
        String fallbackSubject,
        String fallbackBody
    ) {
        Id templateId = getTemplateId(templateDeveloperName);
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Appointment__c appointment : appointments) {
            if (String.isBlank(appointment.Patient_Email__c)) {
                continue;
            }

            Messaging.SingleEmailMessage email = templateId != null ? renderTemplate(templateId, appointment.Id) : null;
            if (email == null) {
                email = new Messaging.SingleEmailMessage();
                email.setSubject(fallbackSubject);
                email.setPlainTextBody(mergeAppointment(fallbackBody, appointment));
            }
            email.setToAddresses(new List<String>{ appointment.Patient_Email__c });
            email.setSaveAsActivity(false);
            emails.add(email);
        }

        send(emails);
    }

    /** Sends a plain email to any list of addresses (doctors, finance team, admins). */
    public static void sendEmail(List<String> toAddresses, String subject, String body) {
        List<String> recipients = new List<String>();
        for (String address : toAddresses == null ? new List<String>() : toAddresses) {
            if (String.isNotBlank(address)) {
                recipients.add(address.trim());
            }
        }
        if (recipients.isEmpty()) {
            return;
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(recipients);
        email.setSubject(subject);
        email.setPlainTextBody(body);
        send(new List<Messaging.SingleEmailMessage>{ email });
    }

    /** Emails each doctor (Doctor__c.Email__c) the same message. */
    public static void sendDoctorEmails(List<Doctor__c> doctors, String subject, String body) {
        List<String> addresses = new List<String>();
        for (Doctor__c doctor : doctors) {
            addresses.add(doctor.Email__c);
        }
        sendEmail(addresses, subject, body);
    }

    @TestVisible
    private static void send(List<Messaging.SingleEmailMessage> emails) {
        if (emails.isEmpty()) {
            return;
        }
        if (Limits.getEmailInvocations() >= Limits.getLimitEmailInvocations()) {
            System.debug(LoggingLevel.WARN, 'Email invocation limit reached; ' + emails.size() + ' emails skipped.');
            return;
        }

        emailsQueued += emails.size();
        try {
            Messaging.sendEmail(emails, false);
        } catch (EmailException e) {
            // Thrown when deliverability is off (common in dev/test orgs).
            System.debug(LoggingLevel.WARN, 'Email not sent: ' + e.getMessage());
        }
    }

    private static Messaging.SingleEmailMessage renderTemplate(Id templateId, Id whatId) {
        try {
            Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templateId, null, whatId);
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setSubject(rendered.getSubject());
            email.setPlainTextBody(rendered.getPlainTextBody());
            if (String.isNotBlank(rendered.getHtmlBody())) {
                email.setHtmlBody(rendered.getHtmlBody());
            }
            return email;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Template render failed, using fallback: ' + e.getMessage());
            return null;
        }
    }

    private static Map<String, Id> templateCache;

    private static Id getTemplateId(String developerName) {
        if (String.isBlank(developerName)) {
            return null;
        }
        if (templateCache == null) {
            templateCache = new Map<String, Id>();
            for (EmailTemplate template : [
                SELECT Id, DeveloperName
                FROM EmailTemplate
                WHERE DeveloperName IN (:TEMPLATE_CANCELLATION, :TEMPLATE_REMINDER, 'Appointment_Confirmation_Template')
            ]) {
                templateCache.put(template.DeveloperName, template.Id);
            }
        }
        return templateCache.get(developerName);
    }

    private static String mergeAppointment(String body, Appointment__c appointment) {
        String dateText = appointment.Appointment_Date__c == null ? '' : appointment.Appointment_Date__c.format();
        return body.replace('{date}', dateText).replace('{slot}', appointment.Slot__c == null ? '' : appointment.Slot__c);
    }
}
