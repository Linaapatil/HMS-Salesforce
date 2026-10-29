import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAppointmentsByDoctor from '@salesforce/apex/AppointmentScheduler.getAppointmentsByDoctor';
import getCurrentDoctorId from '@salesforce/apex/AppointmentScheduler.getCurrentDoctorId';

export function toIsoDate(date) {
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
}

/**
 * Doctor portal: a doctor's daily schedule and patient list in card format.
 * - Props: doctorId (from the parent dashboard) and selectedDate. On a Doctor record page the
 *   recordId is used; standalone (e.g. Home page) it shows the running user's own schedule.
 * - Wire: AppointmentScheduler.getAppointmentsByDoctor
 * - Events: appointmentselected (fires on row click)
 */
export default class DoctorScheduleCard extends LightningElement {
    @api doctorId;
    @api recordId;
    @api cardTitle = 'Doctor Schedule';

    _selectedDate;
    @api
    get selectedDate() {
        return this._selectedDate || toIsoDate(new Date());
    }
    set selectedDate(value) {
        this._selectedDate = value;
    }

    currentUserDoctorId;
    appointments;
    error;
    wiredResult;

    @wire(getCurrentDoctorId)
    wiredCurrentDoctor({ data }) {
        if (data) {
            this.currentUserDoctorId = data;
        }
    }

    get effectiveDoctorId() {
        return this.doctorId || this.recordId || this.currentUserDoctorId;
    }

    @wire(getAppointmentsByDoctor, { doctorId: '$effectiveDoctorId', appointmentDate: '$selectedDate' })
    wiredAppointments(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.appointments = data.map((appointment) => ({
                ...appointment,
                patientName: appointment.Patient__r ? appointment.Patient__r.Full_Name__c || appointment.Patient__r.Name : 'Unknown patient',
                patientNumber: appointment.Patient__r ? appointment.Patient__r.Name : '',
                statusClass: `status-badge status-${(appointment.Status__c || 'requested').toLowerCase()}`
            }));
            this.error = undefined;
        } else if (error) {
            this.appointments = undefined;
            this.error = error;
        }
    }

    get hasDoctor() {
        return Boolean(this.effectiveDoctorId);
    }

    get hasAppointments() {
        return Array.isArray(this.appointments) && this.appointments.length > 0;
    }

    get appointmentCountLabel() {
        const count = this.appointments ? this.appointments.length : 0;
        return `${count} ${count === 1 ? 'Appointment' : 'Appointments'}`;
    }

    /** Lets the parent re-query after a booking. */
    @api
    refresh() {
        return this.wiredResult ? refreshApex(this.wiredResult) : Promise.resolve();
    }

    handleAppointmentClick(event) {
        this.dispatchEvent(new CustomEvent('appointmentselected', { detail: event.currentTarget.dataset.id }));
    }
}
