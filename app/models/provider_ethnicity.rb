class ProviderEthnicity < ActiveRecord::Base
  belongs_to :provider

  validates :name, :length => { :minimum => 2 }

  default_scope { order('name') }

  has_paper_trail
end
