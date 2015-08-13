require 'geohash'

class Device < ActiveRecord::Base

  belongs_to :owner
  belongs_to :kit

  belongs_to :owner, class_name: 'User'
  validates_presence_of :owner, :mac_address, :name
  # validates_presence_of :mac_address, :name

  # validates :mac_address, uniqueness: true, format: { with: /\A([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\z/ }#, unless: Proc.new { |d| d.mac_address == 'unknown' }
  validates_uniqueness_of :mac_address#, on: :create
  validates_format_of :mac_address, with: /\A([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\z/#, on: :create, allow_blank: true

  default_scope { includes :owner }

  # temporary kit getter/setter
  def kit_version
    if self.kit_id
      "1.0" if self.kit_id = 2
      "1.1" if self.kit_id = 3
    end
  end

  def kit_version=(kv)
    if kv == "1.0"
      self.kit_id = 2
    elsif kv == "1.1"
      self.kit_id = 3
    end
  end

  # delegate :username, :to => :owner, :prefix => true

  def owner_username
    owner.username if owner
  end

  include PgSearch
  multisearchable :against => [:name, :description, :city, :country_name]#, associated_against: { owner: { :username }

  has_many :pg_readings

  def country_name
    country ? country.to_s : nil
  end

  validate :banned_name
  def banned_name
    if name.present? and Smartcitizen::Application.config.banned_words.include?(name.downcase.strip)
      errors.add(:name, "is reserved")
    end
  end

  # reverse_geocoded_by :latitude, :longitude
  reverse_geocoded_by :latitude, :longitude do |obj, results|
    if geo = results.first
      obj.address = geo.address
      obj.city = geo.city
      obj.postal_code = geo.postal_code
      obj.state = geo.state
      obj.state_code = geo.state_code
      obj.country = geo.country
      obj.country_code = geo.country_code
    end
  end
  # after_validation :reverse_geocode

  after_initialize :set_default_name

  # these get overridden the device is a kit
  has_many :components, as: :board
  has_many :sensors, through: :components

  before_save :calculate_geohash

  store_accessor :location,
    :address,
    :city,
    :postal_code,
    :state,
    :state_code,
    :country,
    :country_code

  store_accessor :meta,
    :elevation,
    :exposure,
    :firmware_version,
    :smart_cal,
    :debug_push,
    :enclosure_type

  def system_tags
    [
      exposure, # indoor / outdoor
      ('new' if created_at > 1.week.ago), # new
      ((last_recorded_at.present? and last_recorded_at > 10.minutes.ago) ? 'online' : 'offline') # state
    ].compact.sort
  end

  def to_s
    name
  end

  def added_at
    created_at
  end

  def last_reading_at
    last_recorded_at
  end

  def firmware
    if firmware_version.present?
      "sck:#{firmware_version}"
    end
  end

  def components
    kit ? kit.components : super
  end

  def sensors
    kit ? kit.sensors : super
  end

  def status
    data.present? ? state : 'new'
  end

  def state
    if data.present?
      'has_published'
    elsif mac_address.present?
      'never_published'
    else
      'not_configured'
    end
  end

  def formatted_data
    s = {
      recorded_at: updated_at,
      added_at: updated_at,
      # calibrated_at: updated_at,
      firmware: "[IGNORE]",
      location: {
        ip: nil,
        exposure: exposure,
        elevation: elevation.try(:to_i) ,
        latitude: latitude,
        longitude: longitude,
        geohash: geohash,
        city: city,
        country_code: country_code,
        country: country
      },
      sensors: []
    }

    sensors.sort_by(&:name).each do |sensor|
      sa = sensor.attributes
      sa = sa.merge(
        value: (data ? data["#{sensor.id}"] : nil),
        raw_value: (data ? data["#{sensor.id}_raw"] : nil),
        prev_value: (old_data ? old_data["#{sensor.id}"] : nil),
        prev_raw_value: (old_data ? old_data["#{sensor.id}_raw"] : nil)
      )
      s[:sensors] << sa
    end

    return s
  end

  # def self.lightning
  #   connection.select_all(select(%w(old_data)).arel, nil, all.bind_values).each do |attrs|
  #     attrs.each do |name, value|
  #       attrs[name] = column_types[name].type_cast_from_database(value)
  #     end
  #   end
  # end

  def self.lightning
    ds = []
    Device.connection.select_all(select(%w(migration_data)).order(:id).arel, nil, all.bind_values).each do |attrs|
      attrs.values.each do |hash|
        begin
          hash = Oj.load(hash)
          d = {}
          d['id'] = hash['id'].try(:to_s)
          d['title'] = hash['title'].try(:to_s)
          # d['username'] = hash['username'].try(:to_s)
          d['description'] = hash['description'].to_s#.encode("ISO-8859-1")
          d['city'] = hash['city'].try(:to_s)
          d['country'] = hash['country'].try(:to_s)
          d['exposure'] = hash['exposure'].try(:to_s)
          d['elevation'] = hash['elevation'].try(:to_s)
          d['geo_lat'] = hash['geo_lat']#.split('.').each_with_index.map{|n,i| n }
          d['geo_lng'] = hash['geo_lng']#.split('.').each_with_index.map{|n,i| n }
          d['created'] = hash['created'].gsub('T', ' ').gsub('Z', ' UTC')
          d['last_insert_datetime'] = hash['modified'].gsub('T', ' ').gsub('Z', ' UTC')
          ds << d
        rescue NoMethodError
        end
      end
    end
    ds
  end

  def legacy_serialize
    {
      id: id,
      description: description,
      city: city,
      country: country_name,
      exposure: exposure,
      elevation: elevation.try(:to_f),
      title: name,
      location: city,
      geo_lat: latitude,
      geo_lng: longitude,
      created: created_at,
      last_insert_datetime: updated_at
    }
  end

private

  def calculate_geohash
    # include ActiveModel::Dirty
    # if latitude.changed? or longitude.changed?
    if latitude.is_a?(Float) and longitude.is_a?(Float)
      self.geohash = GeoHash.encode(latitude, longitude)
    end
  end

  def set_default_name
    self.name ||= "My SCK"
  end

end


# REDIS
# online_kits = [12,13,4,546,45,4564,46,75,68,97] - TTL 15 minutes? // last_recorded_at
# online? - online_kits.include?(id)
# offline? - !online_kits.include?(id)

# exposure - indoor / outdoor
# search by name, city & description
# date range - granulation hour/day/week/month/year/lifetime
# filter by:
#   online
#   offline
#   kit type
#   firmware version
#   ...
