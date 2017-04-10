class Address < ActiveRecord::Base
  acts_as_paranoid # soft delete
  
  belongs_to :provider, -> { with_deleted }

  belongs_to :customer, -> { with_deleted }, inverse_of: :addresses

  has_one :driver

  belongs_to :trip_purpose, -> { with_deleted }
  delegate :name, to: :trip_purpose, prefix: :trip_purpose, allow_nil: true
  
  has_many :trips_from, :class_name => "Trip", :foreign_key => :pickup_address_id
  has_many :trips_to, :class_name => "Trip", :foreign_key => :dropoff_address_id

  normalize_attribute :name, :with=> [:squish, :titleize]
  normalize_attribute :building_name, :with=> [:squish, :titleize]
  normalize_attribute :address, :with=> [:squish, :titleize]
  normalize_attribute :city, :with=> [:squish, :titleize]

  validates :address, :length => { :minimum => 5, :unless => :geocoded? }
  validates :city,    :length => { :minimum => 2, :unless => :geocoded? }
  validates :state,   :length => { :is => 2, :unless => :geocoded? }
  validates :zip,     :length => { :is => 5, :if => lambda { |a| a.zip.present? } }
  validate :address_presented # must be put below above validations (address/city/state/zip)
  
  before_validation :compute_in_district

  has_paper_trail
  
  NewAddressOption = { :label => "New Address", :id => 0 }

  scope :for_provider,    -> (provider) { where(:provider_id => provider.id) }
  scope :search_for_term, -> (term) { where("LOWER(name) LIKE '%' || :term || '%' OR LOWER(building_name) LIKE '%' || :term || '%' OR LOWER(address) LIKE '%' || :term || '%'",{:term => term}) }

  def trips
    trips_from + trips_to
  end
  
  def replace_with!(address_id)
    return false unless address_id.present? && self.class.exists?(address_id)
    
    self.trips_from.update_all pickup_address_id: address_id
    
    self.trips_to.update_all dropoff_address_id: address_id
    
    self.destroy
    self.class.find address_id
  end
  
  def compute_in_district
    if the_geom and in_district.nil?
      in_district = Region.count(:conditions => ["is_primary = 't' and st_contains(the_geom, ?)", the_geom]) > 0
      true # avoid returning false while doing before_validation
    end 
  end

  def latitude
    the_geom.y if the_geom
  end

  def longitude
    the_geom.x if the_geom
  end

  def latitude=(y)
    the_geom.y = y if the_geom
  end

  def longitude=(x)
    the_geom.x = x if the_geom
  end

  def geocoded?
    !the_geom.nil?
  end

  def text
    if building_name.to_s.size > 0 and name.to_s.size > 0
      first_line = "%s - %s\n" % [name, building_name]
    elsif building_name.to_s.size > 0
      first_line = building_name + "\n"
    elsif name.to_s.size > 0
      first_line = name + "\n"
    else
      first_line = ''
    end

    ("%s %s \n%s, %s %s" % [first_line, address, city, state, zip]).strip

  end

  def one_line_text
    text.gsub(/\s+/, ' ')
  end

  def address_text
    (
      (address.blank? ? '' : address + ", " ) +
      (city.blank? ?  '' : city + ", " ) +
      ("%s %s" % [state, zip])
    ).strip 
  end

  def json
    {
      :label => text, 
      :id => id, 
      :name => name,
      :building_name => building_name,
      :address => address,
      :city => city,
      :state => state,
      :zip => zip,
      :in_district => in_district,
      :phone_number => phone_number,
      :lat => latitude,
      :lon => longitude,
      :default_trip_purpose => trip_purpose_name,
      :trip_purpose_id => trip_purpose.try(:id),
      :notes => notes
    }
  end

  def address_presented
    errors.add(:base, TranslationEngine.translate_text(:address_required)) if !address_text.present?
  end

end
