import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import getTodayStats from '@salesforce/apex/HospitalDashboardController.getTodayStats';
import getRevenueSummary from '@salesforce/apex/HospitalDashboardController.getRevenueSummary';
import getBedOccupancy from '@salesforce/apex/HospitalDashboardController.getBedOccupancy';
import getDepartmentSummary from '@salesforce/apex/HospitalDashboardController.getDepartmentSummary';
import APPOINTMENT_REFRESH from '@salesforce/messageChannel/Appointment_Refresh__c';
import { toIsoDate } from 'c/doctorScheduleCard';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY_CODE from '@salesforce/i18n/currency';

// Formats amounts in the running user's locale and currency, matching standard record pages.
const CURRENCY = new Intl.NumberFormat(LOCALE, { style: 'currency', currency: CURRENCY_CODE, maximumFractionDigits: 0 });

/**
 * Hospital admin dashboard.
 * - Multiple imperative Apex calls for today's stats, revenue and bed occupancy
 * - Rendering loop (for:each) for the department-wise summary table
 * - Parent of doctorScheduleCard (passes doctorId + selectedDate) and appointmentForm
 *   (handles its `appointmentsaved` event to refresh the stats)
 * - LMS: subscribes to APPOINTMENT_REFRESH so bookings made anywhere on the page refresh it
 */
export default class HospitalDashboard extends NavigationMixin(LightningElement) {
    selectedDate = toIsoDate(new Date());
    selectedDoctorId;

    todayStats = { totalAppointments: 0, upcoming: 0, completed: 0, cancelled: 0, activeDoctors: 0 };
    revenue = { monthRevenue: 0, monthInsurance: 0, monthBills: 0, pendingApprovals: 0 };
    beds = { totalBeds: 0, occupiedBeds: 0, occupancyPercent: 0 };
    departmentSummary = [];
    isLoading = true;
    error;
    subscription;

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        this.loadDashboardData();
        if (!this.subscription) {
            this.subscription = subscribe(this.messageContext, APPOINTMENT_REFRESH, () => this.refreshAll(), { scope: APPLICATION_SCOPE });
        }
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    async loadDashboardData() {
        this.isLoading = true;
        try {
            const [stats, revenue, beds, departments] = await Promise.all([
                getTodayStats(),
                getRevenueSummary(),
                getBedOccupancy(),
                getDepartmentSummary()
            ]);
            this.todayStats = stats;
            this.revenue = revenue;
            this.beds = beds;
            this.departmentSummary = (departments || []).map((row, index) => ({
                ...row,
                key: row.departmentId || `unassigned-${index}`,
                occupancyLabel: row.bedCount ? `${row.occupiedBeds}/${row.bedCount} (${Math.round((row.occupiedBeds * 100) / row.bedCount)}%)` : '—',
                occupancyStyle: `width: ${row.bedCount ? Math.min(100, Math.round((row.occupiedBeds * 100) / row.bedCount)) : 0}%`
            }));
            this.error = undefined;
        } catch (error) {
            this.error = error;
        } finally {
            this.isLoading = false;
        }
    }

    refreshAll() {
        this.loadDashboardData();
        const schedule = this.template.querySelector('c-doctor-schedule-card');
        if (schedule) {
            schedule.refresh();
        }
    }

    get monthRevenueLabel() {
        return CURRENCY.format(this.revenue.monthRevenue || 0);
    }

    get insuranceLabel() {
        return `${CURRENCY.format(this.revenue.monthInsurance || 0)} covered by insurance`;
    }

    get occupancyLabel() {
        return `${this.beds.occupiedBeds} of ${this.beds.totalBeds} beds occupied`;
    }

    get todayBreakdown() {
        return `${this.todayStats.upcoming} upcoming · ${this.todayStats.completed} completed · ${this.todayStats.cancelled} cancelled`;
    }

    get hasDepartments() {
        return this.departmentSummary.length > 0;
    }

    handleDoctorChange(event) {
        this.selectedDoctorId = event.detail.recordId;
    }

    handleDateChange(event) {
        this.selectedDate = event.target.value;
    }

    /** Child -> parent: appointmentForm fires `appointmentsaved` after a booking. */
    handleAppointmentSaved() {
        this.refreshAll();
    }

    handleAppointmentSelected(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.detail, objectApiName: 'Appointment__c', actionName: 'view' }
        });
    }

    handleDepartmentClick(event) {
        const departmentId = event.currentTarget.dataset.id;
        if (!departmentId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: departmentId, objectApiName: 'Department__c', actionName: 'view' }
        });
    }
}
