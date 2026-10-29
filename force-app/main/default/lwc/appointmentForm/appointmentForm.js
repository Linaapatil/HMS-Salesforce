import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, publish, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';

import APPOINTMENT_OBJECT from '@salesforce/schema/Appointment__c';
import DOCTOR_NAME from '@salesforce/schema/Doctor__c.Name';
import DOCTOR_SPECIALIZATION from '@salesforce/schema/Doctor__c.Specialization__c';
import DOCTOR_STATUS from '@salesforce/schema/Doctor__c.Status__c';
import DOCTOR_AVAILABILITY from '@salesforce/schema/Doctor__c.Availability__c';
import DOCTOR_WORKLOAD from '@salesforce/schema/Doctor__c.Active_Appointments__c';
import PATIENT_SELECTED from '@salesforce/messageChannel/Patient_Selected__c';
import APPOINTMENT_REFRESH from '@salesforce/messageChannel/Appointment_Refresh__c';

const DOCTOR_FIELDS = [DOCTOR_NAME, DOCTOR_SPECIALIZATION, DOCTOR_STATUS, DOCTOR_AVAILABILITY, DOCTOR_WORKLOAD];
export const SPECIALIST_RECORD_TYPE = 'Specialist Consultation';

/**
 * Screen to book a new appointment.
 * - LDS: getObjectInfo for record types, @wire getRecord for the selected doctor's availability
 * - Conditional rendering: specialist fields only for the Specialist Consultation record type
 * - LMS: consumes PATIENT_SELECTED (from patientSearchBar), publishes APPOINTMENT_REFRESH
 * - Fires `appointmentsaved` to the parent (hospitalDashboard) and navigates to the new record
 */
export default class AppointmentForm extends NavigationMixin(LightningElement) {
    /** When true (e.g. embedded in the dashboard) the form resets instead of navigating away. */
    @api stayOnPage = false;

    recordTypeOptions = [];
    selectedRecordTypeId;
    selectedPatientId;
    selectedDoctorId;
    subscription;

    @wire(MessageContext)
    messageContext;

    @wire(getObjectInfo, { objectApiName: APPOINTMENT_OBJECT })
    appointmentObjectInfo({ data, error }) {
        if (data) {
            this.recordTypeOptions = Object.values(data.recordTypeInfos)
                .filter((recordType) => recordType.available && !recordType.master)
                .map((recordType) => ({ label: recordType.name, value: recordType.recordTypeId }));
            if (!this.selectedRecordTypeId) {
                this.selectedRecordTypeId = data.defaultRecordTypeId;
            }
        } else if (error) {
            this.recordTypeOptions = [];
        }
    }

    @wire(getRecord, { recordId: '$selectedDoctorId', fields: DOCTOR_FIELDS })
    doctor;

    get isSpecialist() {
        const selected = this.recordTypeOptions.find((option) => option.value === this.selectedRecordTypeId);
        return selected?.label === SPECIALIST_RECORD_TYPE;
    }

    get hasDoctor() {
        return Boolean(this.selectedDoctorId && this.doctor?.data);
    }

    get doctorName() {
        return getFieldValue(this.doctor?.data, DOCTOR_NAME);
    }

    get doctorSpecialization() {
        return getFieldValue(this.doctor?.data, DOCTOR_SPECIALIZATION) || 'General';
    }

    get doctorAvailability() {
        return getFieldValue(this.doctor?.data, DOCTOR_AVAILABILITY) || 'Unknown';
    }

    get doctorWorkload() {
        return getFieldValue(this.doctor?.data, DOCTOR_WORKLOAD) || 0;
    }

    get isDoctorBookable() {
        return getFieldValue(this.doctor?.data, DOCTOR_STATUS) === 'Active';
    }

    get doctorStatusClass() {
        return this.isDoctorBookable ? 'doctor-status available' : 'doctor-status unavailable';
    }

    get doctorStatusLabel() {
        return this.isDoctorBookable ? 'Available for booking' : 'On leave / inactive';
    }

    get isSubmitDisabled() {
        return this.hasDoctor && !this.isDoctorBookable;
    }

    connectedCallback() {
        if (!this.subscription) {
            this.subscription = subscribe(this.messageContext, PATIENT_SELECTED, (message) => this.handlePatientSelected(message), {
                scope: APPLICATION_SCOPE
            });
        }
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    handlePatientSelected(message) {
        this.selectedPatientId = message?.patientId;
    }

    handleRecordTypeChange(event) {
        this.selectedRecordTypeId = event.detail.value;
    }

    handleDoctorChange(event) {
        const value = event.detail.value;
        this.selectedDoctorId = Array.isArray(value) ? value[0] : value;
    }

    handlePatientChange(event) {
        const value = event.detail.value;
        this.selectedPatientId = Array.isArray(value) ? value[0] : value;
    }

    handleSuccess(event) {
        const appointmentId = event.detail.id;

        publish(this.messageContext, APPOINTMENT_REFRESH, { appointmentId });
        this.dispatchEvent(new CustomEvent('appointmentsaved', { detail: appointmentId }));
        this.dispatchEvent(new ShowToastEvent({ title: 'Appointment booked', message: 'The appointment was created.', variant: 'success' }));

        if (this.stayOnPage) {
            this.resetForm();
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: appointmentId, objectApiName: 'Appointment__c', actionName: 'view' }
        });
    }

    handleError(event) {
        this.dispatchEvent(
            new ShowToastEvent({ title: 'Could not book appointment', message: event.detail?.detail || event.detail?.message, variant: 'error' })
        );
    }

    resetForm() {
        this.template.querySelectorAll('lightning-input-field').forEach((field) => {
            if (field.fieldName !== 'Status__c') {
                field.reset();
            }
        });
        this.selectedDoctorId = undefined;
        this.selectedPatientId = undefined;
    }
}
