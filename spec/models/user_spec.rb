# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                               :integer          not null, primary key
#  admin                            :boolean          default(FALSE)
#  email_address                    :string(255)
#  email_verification_token         :string(255)
#  email_verified_at                :datetime
#  first_name                       :string(255)
#  last_name                        :string(255)
#  password_digest                  :string(255)
#  password_reset_token             :string(255)
#  password_reset_token_valid_until :datetime
#  time_zone                        :string(255)
#  uuid                             :string(255)
#  created_at                       :datetime
#  updated_at                       :datetime
#
# Indexes
#
#  index_users_on_email_address  (email_address)
#  index_users_on_uuid           (uuid)
#
require "rails_helper"

describe User do
  context "model" do
    subject(:user) { create(:user) }

    it "should have a UUID" do
      expect(user.uuid).to be_a String
      expect(user.uuid.length).to eq 36
    end
  end

  context ".authenticate" do
    it "should not authenticate users with invalid emails" do
      expect { User.authenticate("nothing@nothing.com", "hello") }.to raise_error(Postal::Errors::AuthenticationError) do |e|
        expect(e.error).to eq "InvalidEmailAddress"
      end
    end

    it "should not authenticate users with invalid passwords" do
      user = create(:user)
      expect { User.authenticate(user.email_address, "hello") }.to raise_error(Postal::Errors::AuthenticationError) do |e|
        expect(e.error).to eq "InvalidPassword"
      end
    end

    it "should authenticate valid users" do
      user = create(:user)
      auth_user = nil
      expect { auth_user = User.authenticate(user.email_address, "passw0rd") }.to_not raise_error
      expect(auth_user).to eq user
    end
  end
end
