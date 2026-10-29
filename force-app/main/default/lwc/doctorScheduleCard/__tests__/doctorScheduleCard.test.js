import { createElement } from '@lwc/engine-dom';
import DoctorScheduleCard, { toIsoDate } from 'c/doctorScheduleCard';
import getAppointmentsByDoctor from '@salesforce/apex/AppointmentScheduler.getAppointmentsByDoctor';

jest.mock(
    '@salesforce/apex/AppointmentScheduler.getAppointmentsByDoctor',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/AppointmentScheduler.getCurrentDoctorId',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

const APPOINTMENTS = [
    {
        Id: 'a02000000000001AAA',
        Slot__c: '09:00 AM',
        Status__c: 'Confirmed',
        Appointment_Type__c: 'General Consultation',
        Patient__r: { Name: 'PAT-0001', Full_Name__c: 'Ananya Sharma' }
    },
    {
        Id: 'a02000000000002AAA',
        Slot__c: '10:00 AM',
        Status__c: 'Requested',
        Appointment_Type__c: 'Specialist Consultation',
        Patient__r: { Name: 'PAT-0002' }
    }
];

const flushPromises = () => new Promise((resolve) => process.nextTick(resolve));

function createComponent(props = {}) {
    const element = createElement('c-doctor-schedule-card', { is: DoctorScheduleCard });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
}

describe('c-doctor-schedule-card', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('formats dates in local time', () => {
        expect(toIsoDate(new Date(2026, 0, 5))).toBe('2026-01-05');
    });

    it('asks for a doctor when none is selected', () => {
        const element = createComponent();
        expect(element.shadowRoot.querySelector('.empty-state h3').textContent).toBe('Select a doctor');
    });

    it('renders appointments in card format with patient names', async () => {
        const element = createComponent({ doctorId: 'a03000000000001AAA', selectedDate: '2026-11-02' });
        getAppointmentsByDoctor.emit(APPOINTMENTS);
        await flushPromises();

        const cards = element.shadowRoot.querySelectorAll('.appointment-card');
        expect(cards).toHaveLength(2);
        expect(cards[0].querySelector('.patient-name').textContent).toBe('Ananya Sharma');
        expect(cards[1].querySelector('.patient-name').textContent).toBe('PAT-0002');
        expect(cards[0].querySelector('.status-badge').className).toContain('status-confirmed');
        expect(element.shadowRoot.querySelector('.appointment-count').textContent).toBe('2 Appointments');
        expect(getAppointmentsByDoctor.getLastConfig()).toEqual({ doctorId: 'a03000000000001AAA', appointmentDate: '2026-11-02' });
    });

    it('uses the record id on a Doctor record page', async () => {
        createComponent({ recordId: 'a03000000000009AAA' });
        await flushPromises();

        expect(getAppointmentsByDoctor.getLastConfig().doctorId).toBe('a03000000000009AAA');
    });

    it('shows the empty state for a day without appointments', async () => {
        const element = createComponent({ doctorId: 'a03000000000001AAA' });
        getAppointmentsByDoctor.emit([]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.empty-state h3').textContent).toBe('No appointments scheduled');
    });

    it('shows an error state when the wire fails', async () => {
        const element = createComponent({ doctorId: 'a03000000000001AAA' });
        getAppointmentsByDoctor.error();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.error-state')).not.toBeNull();
    });

    it('fires appointmentselected with the appointment id on row click', async () => {
        const element = createComponent({ doctorId: 'a03000000000001AAA' });
        const handler = jest.fn();
        element.addEventListener('appointmentselected', handler);
        getAppointmentsByDoctor.emit(APPOINTMENTS);
        await flushPromises();

        element.shadowRoot.querySelectorAll('.appointment-card')[1].click();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toBe('a02000000000002AAA');
    });
});
