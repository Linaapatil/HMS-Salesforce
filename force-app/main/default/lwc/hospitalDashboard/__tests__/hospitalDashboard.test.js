import { createElement } from '@lwc/engine-dom';
import HospitalDashboard from 'c/hospitalDashboard';
import getTodayStats from '@salesforce/apex/HospitalDashboardController.getTodayStats';
import getRevenueSummary from '@salesforce/apex/HospitalDashboardController.getRevenueSummary';
import getBedOccupancy from '@salesforce/apex/HospitalDashboardController.getBedOccupancy';
import getDepartmentSummary from '@salesforce/apex/HospitalDashboardController.getDepartmentSummary';
import { subscribe } from 'lightning/messageService';

jest.mock('@salesforce/apex/HospitalDashboardController.getTodayStats', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/HospitalDashboardController.getRevenueSummary', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/HospitalDashboardController.getBedOccupancy', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/HospitalDashboardController.getDepartmentSummary', () => ({ default: jest.fn() }), { virtual: true });
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

const STATS = { totalAppointments: 12, upcoming: 7, completed: 4, cancelled: 1, activeDoctors: 6 };
const REVENUE = { monthRevenue: 245000, monthInsurance: 50000, monthBills: 30, pendingApprovals: 2 };
const BEDS = { totalBeds: 200, occupiedBeds: 150, occupancyPercent: 75 };
const DEPARTMENTS = [
    { departmentId: 'a04000000000001AAA', department: 'Cardiology', headOfDepartment: 'Dr. Meera Iyer', floor: 3, bedCount: 40, occupiedBeds: 30, appointmentCount: 5 },
    { departmentId: null, department: 'Not Assigned', bedCount: 0, occupiedBeds: 0, appointmentCount: 1 }
];

const flushPromises = () => new Promise((resolve) => process.nextTick(resolve));

function mockApex() {
    getTodayStats.mockResolvedValue(STATS);
    getRevenueSummary.mockResolvedValue(REVENUE);
    getBedOccupancy.mockResolvedValue(BEDS);
    getDepartmentSummary.mockResolvedValue(DEPARTMENTS);
}

function createComponent() {
    const element = createElement('c-hospital-dashboard', { is: HospitalDashboard });
    document.body.appendChild(element);
    return element;
}

describe('c-hospital-dashboard', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads all stats with multiple imperative Apex calls', async () => {
        mockApex();
        const element = createComponent();
        await flushPromises();

        expect(getTodayStats).toHaveBeenCalledTimes(1);
        expect(getRevenueSummary).toHaveBeenCalledTimes(1);
        expect(getBedOccupancy).toHaveBeenCalledTimes(1);
        expect(getDepartmentSummary).toHaveBeenCalledTimes(1);

        expect(element.shadowRoot.querySelector('[data-id="today-count"]').textContent).toBe('12');
        expect(element.shadowRoot.querySelector('[data-id="bed-occupancy"]').textContent).toBe('75%');
        // Jest's i18n stubs are en-US / USD; in the org this follows the user's locale and currency.
        expect(element.shadowRoot.querySelector('[data-id="month-revenue"]').textContent).toBe('$245,000');
    });

    it('renders the department-wise summary table with a rendering loop', async () => {
        mockApex();
        const element = createComponent();
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('.department-table tbody tr');
        expect(rows).toHaveLength(2);
        expect(rows[0].querySelector('.department-name').textContent).toBe('Cardiology');
        expect(rows[0].querySelector('.occupancy-text').textContent).toBe('30/40 (75%)');
        expect(rows[1].querySelector('.occupancy-text').textContent).toBe('—');
    });

    it('passes the selected doctor and date down to doctorScheduleCard', async () => {
        mockApex();
        const element = createComponent();
        await flushPromises();

        element.shadowRoot.querySelector('lightning-record-picker').dispatchEvent(new CustomEvent('change', { detail: { recordId: 'a03000000000001AAA' } }));
        const dateInput = [...element.shadowRoot.querySelectorAll('lightning-input')].find((input) => input.type === 'date');
        dateInput.value = '2026-11-02';
        dateInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const schedule = element.shadowRoot.querySelector('c-doctor-schedule-card');
        expect(schedule.doctorId).toBe('a03000000000001AAA');
        expect(schedule.selectedDate).toBe('2026-11-02');
    });

    it('refreshes stats when the child appointmentForm fires appointmentsaved', async () => {
        mockApex();
        const element = createComponent();
        await flushPromises();

        element.shadowRoot.querySelector('c-appointment-form').dispatchEvent(new CustomEvent('appointmentsaved', { detail: 'a02000000000001AAA' }));
        await flushPromises();

        expect(getTodayStats).toHaveBeenCalledTimes(2);
    });

    it('refreshes stats on an APPOINTMENT_REFRESH message', async () => {
        mockApex();
        createComponent();
        await flushPromises();

        const handler = subscribe.mock.calls.find((call) => call[1] && String(call[1]).includes('Appointment_Refresh'))[2];
        handler({ appointmentId: 'a02000000000001AAA' });
        await flushPromises();

        expect(getTodayStats).toHaveBeenCalledTimes(2);
    });

    it('shows an error when stats fail to load', async () => {
        mockApex();
        getTodayStats.mockRejectedValue({ body: { message: 'boom' } });
        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.error-message')).not.toBeNull();
    });
});
