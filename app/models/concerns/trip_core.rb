require 'active_support/concern'

module TripCore
  extend ActiveSupport::Concern

  included do
    belongs_to :customer, -> { with_deleted }
    belongs_to :dropoff_address,  -> { with_deleted }, class_name: "Address"
    belongs_to :funding_source, -> { with_deleted }
    belongs_to :mobility, -> { with_deleted }
    belongs_to :pickup_address, -> { with_deleted }, class_name: "Address"
    belongs_to :provider, -> { with_deleted }
    belongs_to :service_level, -> { with_deleted }
    belongs_to :trip_purpose, -> { with_deleted }


    delegate :name, to: :service_level, prefix: :service_level, allow_nil: true
    delegate :name, to: :customer, prefix: :customer, allow_nil: true
    delegate :name, to: :trip_purpose, prefix: :trip_purpose, allow_nil: true

    validates :appointment_time, presence: true
    validates :attendant_count, numericality: {greater_than_or_equal_to: 0}
    validates :customer, associated: true, presence: true
    validates :dropoff_address, associated: true, presence: true
    validates :guest_count, numericality: {greater_than_or_equal_to: 0}
    validates :pickup_address, associated: true, presence: true
    validates :pickup_time, presence: true
    validates :trip_purpose_id, presence: true
    validates_datetime :appointment_time, presence: true
    validates_datetime :pickup_time, presence: true
    validates :mobility_device_accommodations, numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_blank: true }

    accepts_nested_attributes_for :customer

    scope :after,              -> (pickup_time) { where('pickup_time > ?', pickup_time.utc) }
    scope :after_today,        -> { where('CAST(pickup_time AS date) > ?', Date.today.in_time_zone.utc) }
    scope :today_and_prior,    -> { where('CAST(pickup_time AS date) <= ?', Date.today.in_time_zone.utc) }
    scope :prior_to_today,    -> { where('CAST(pickup_time AS date) < ?', Date.today.in_time_zone.utc) }
    scope :by_funding_source,  -> (name) { includes(:funding_source).references(:funding_source).where("funding_sources.name = ?", name) }
    scope :by_service_level,   -> (level) { includes(:service_level).references(:service_level).where("service_levels.name = ?", level) }
    scope :by_trip_purpose,    -> (name) { includes(:trip_purpose).references(:trip_purpose).where("trip_purposes.name = ?", name) }
    scope :during,             -> (pickup_time, appointment_time) { where('NOT ((pickup_time < ? AND appointment_time < ?) OR (pickup_time > ? AND appointment_time > ?))', pickup_time.utc, appointment_time.utc, pickup_time.utc, appointment_time.utc) }
    scope :for_date,           -> (date) { where('pickup_time >= ? AND pickup_time < ?', date.to_datetime.in_time_zone.utc, date.to_datetime.in_time_zone.utc + 1.day) }
    scope :for_date_range,     -> (from_date, to_date) { where('pickup_time >= ? AND pickup_time < ?', from_date.to_datetime.in_time_zone.utc, to_date.to_datetime.in_time_zone.utc) }
    scope :for_provider,       -> (provider_id) { where(provider_id: provider_id) }
    scope :has_scheduled_time, -> { where.not(pickup_time: nil).where.not(appointment_time: nil) }
    scope :individual,         -> { joins(:customer).where(customers: {group: false}) }
    scope :not_called_back,    -> { where('called_back_at IS NULL') }
    scope :prior_to,           -> (pickup_time) { where('pickup_time < ?', pickup_time.to_datetime.in_time_zone.utc) }
  end

  # Special date attr_reader sends back pickup/appointment time date, or instance var if present
  def date
    @date || pickup_time.to_date || appointment_time.to_date
  end

  # Special date attr_writer sets @date instance variable. Accepts a Date object or a date string
  # This date is used in setting pickup and appointment time attributes
  def date=(date)
    @date = date.is_a?(String) ? Date.parse(date) : date
  end

  def trip_size
    if customer.try(:group)
      group_size
    else
      guest_count + attendant_count + 1
    end
  end

  def trip_count
    trip_size
  end

  def is_in_district?
    pickup_address.try(:in_district) && dropoff_address.try(:in_district)
  end

  def update_donation(user, amount)
    return unless user && amount

    if self.donation
      self.donation.update_attributes(user: user, amount: amount)
    elsif self.id && self.customer
      self.donation = Donation.create(date: Time.current, user: user, customer: self.customer, trip: self, amount: amount)
      self.save
    end
  end

  module ClassMethods
  end
end
