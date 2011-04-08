class Query
  extend ActiveModel::Naming
  include ActiveModel::Conversion

  attr_accessor :start_date
  attr_accessor :end_date
  attr_accessor :vehicle_id

  def convert_date(obj, base)
    return Date.new(obj["#{base}(1i)"].to_i,obj["#{base}(2i)"].to_i,(obj["#{base}(3i)"] || 1).to_i)
  end

  def initialize(params = nil)
    now = Date.today
    @start_date = Date.new(now.year, now.month, 1).prev_month
    @end_date = start_date.next_month
    if params
      if params["start_date(1i)"]
        @start_date = convert_date(params, :start_date)
      end
      if params["end_date(1i)"]
        @end_date = convert_date(params, :end_date)
      end
      if params["vehicle_id"]
        @vehicle_id = params["vehicle_id"]
      end
    end
  end

  def persisted?
    false
  end

end

def bind(args)
  return ActiveRecord::Base.__send__(:sanitize_sql_for_conditions, args, '')
end

class ReportsController < ApplicationController

  def index
  end

  def vehicles
    @vehicles = Vehicle.accessible_by(current_ability)
    @query = Query.new
  end

  def vehicle
    query_params = params[:query]
    @query = Query.new(query_params)
    @vehicles = Vehicle.accessible_by(current_ability)

    @vehicle = Vehicle.accessible_by(current_ability).find @query.vehicle_id
    @start_date = @query.start_date
    @end_date = @start_date.next_month

    @covered_events = @vehicle.vehicle_maintenance_events.where(["service_date BETWEEN ? and ? and reimbursable=true", @start_date, @end_date])

    @noncovered_events = @vehicle.vehicle_maintenance_events.where(["service_date BETWEEN ? and ? and reimbursable=false", @start_date, @end_date])

    month_runs = Run.where(["vehicle_id = ? and date BETWEEN ? and ? ", @vehicle.id, @start_date, @end_date])

    @total_hours = month_runs.sum("start_time - end_time").to_i 
    @total_rides = Trip.find(:all, :joins => :run, :conditions=>{:runs => {:vehicle_id=>@vehicle.id }}).count.to_i #fixme: does not consider guests and attendants -- should it?


    first_run = month_runs.order("date").first
    if first_run
      @beginning_odometer = first_run.start_odometer
      @ending_odometer = month_runs.order("date").last.start_odometer
    else
      #no runs this month
      @beginning_odometer = -1
      @ending_odometer = -1
    end

  end

  def service_summary
    if params[:query]
      query_params = params[:query]
      @query = Query.new(query_params)
      @start_date = @query.start_date
      @monthly = Monthly.where(["start_date = ? and end_date = ?", @start_date, @start_date.next_month]).first
    elsif params[:id]
      @monthly = Monthly.find(params[:id])      
      @start_date = @monthly.start_date
      @end_date = @monthly.end_date
    else
      now = Date.today
      @start_date = Date.new(now.year, now.month, 1).prev_month
    end

    @query = Query.new
    @query.start_date = @start_date
    @end_date = @start_date.next_month
    if @monthly.nil?
      @monthly = Monthly.create(:start_date=>@start_date, :end_date=>@end_date)
    end

    if !can? :read, @monthly
      return redirect_to "/"
    end

    #computes number of trips in and out of district by purpose

    sql = "select trip_purpose, in_district, count(*) as ct from trips where provider_id = ? and pickup_time between ? and ? group by trip_purpose, in_district"

    counts_by_purpose = ActiveRecord::Base.connection.select_all(bind(
        [sql, provider_id, @start_date, @end_date]))

    by_purpose = {}
    for purpose in TRIP_PURPOSES
      by_purpose[purpose] = {'purpose' => purpose, 'in_district' => 0, 'out_of_district' => 0}
    end
    @total = {'in_district' => 0, 'out_of_district' => 0}

    for row in counts_by_purpose
      purpose = row[0]
      if !by_purpose.member? purpose
        next
      end
      if row[1]
        by_purpose[purpose]['in_district'] = row[2]
        @total['in_district'] += row[2]
      else
        by_purpose[purpose]['out_of_district'] = row[2]
        @total['out_of_district'] += row[2]
      end
    end
    @trips_by_purpose = []
    for purpose in TRIP_PURPOSES
      @trips_by_purpose << by_purpose[purpose]
    end
purpose
    #compute monthly totals
    month_runs = Run.where(["provider_id = ? and date BETWEEN ? and ? ", provider_id, @start_date, @end_date])

    first_run = month_runs.order("date").first
    if first_run
      start_odometer = first_run.start_odometer
      end_odometer = month_runs.order("date").last.start_odometer
      @total_miles_driven = end_odometer - start_odometer 
    end

    @turndowns = Trip.where(["provider_id =? and trip_result = 'TD' and pickup_time BETWEEN ? and ? ", provider_id, @start_date, @end_date]).count

    #FIXME: this is not actually goint to work, because you can't 
    #just subtract times in sql and expect to get something useful
    
    @volunteer_driver_hours = month_runs.where("paid = true").sum("end_time - start_time") || 0
    @paid_driver_hours = month_runs.where("paid = false").sum("end_time - start_time")  || 0

    undup_riders_sql = "select count(*) as undup_riders from (select customer_id, fiscal_year(pickup_time) as year, min(fiscal_month(pickup_time)) as month from trips where provider_id=? and trip_result = 'COMP' group by customer_id, year) as  morx where date (year || '-' || month || '-' || 1)  between ? and ? "

    year_start_date = Date.new(@start_date.year, 1, 1)
    year_end_date = year_start_date.next_year

    row = ActiveRecord::Base.connection.select_one(bind([undup_riders_sql, provider_id, year_start_date, year_end_date]))

    @undup_riders = row['undup_riders'].to_i

  end

  def update_monthly
    @monthly = Monthly.find(params[:monthly][:id])

    if can? :edit, @monthly
      @monthly.update_attributes(params[:monthly])
    end
    redirect_to :action=>:service_summary, :id => @monthly.id

  end

  def donations
    query_params = params[:query]
    @query = Query.new(query_params)

    @donations_by_customer = {}
    @total = 0
    for trip in Trip.where(["provider_id = ? and pickup_time between ? and ? and donation > 0", provider_id, @query.start_date, @query.end_date])
      customer = trip.customer
      if ! @donations_by_customer.member? customer
        @donations_by_customer[customer] = trip.donation
      else
        @donations_by_customer[customer] += trip.donation
      end
      @total += trip.donation
    end

    @customers = @donations_by_customer.keys.sort_by {|customer| [customer.last_name, customer.first_name] }

  end

  def cab
    query_params = params[:query]
    @query = Query.new(query_params)

    @trips = Trip.where(["provider_id = ? and pickup_time between ? and ? and cab = true", provider_id, @query.start_date, @query.end_date])
  end

  private
  def provider_id
    return current_user.current_provider_id
  end
end
