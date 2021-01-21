require 'rspec'
require 'bosh/template/evaluation_context'
require 'spec_helper'

describe 'uaa erb generation' do

  let(:generated_script) {
    binding = Bosh::Template::EvaluationContext.new(properties, nil).get_binding
    ERB.new(File.read(script)).result(binding)
  }

  let(:script) { "#{__dir__}/../jobs/uaa/templates/bin/uaa.erb" }

  context 'with postgres and without ldap' do
    let(:properties) {
      {
          'properties' => {
              'uaadb' => {
                  'db_scheme' => 'postgres',
              }
          }
      }
    }

    it 'matches' do
      expect(generated_script).to include("active_spring_profiles=postgresql")
      expect(generated_script).to include("-Dspring.profiles.active=${active_spring_profiles}")
    end
  end

  context 'with mysql and without ldap' do
    let(:properties) {
      {
          'properties' => {
              'uaadb' => {
                  'db_scheme' => 'mysql',
              }
          }
      }
    }

    it 'matches' do
      expect(generated_script).to include("active_spring_profiles=mysql")
      expect(generated_script).to include("-Dspring.profiles.active=${active_spring_profiles}")
    end
  end

  context 'with random db_scheme and without ldap' do
    let(:properties) {
      {
          'properties' => {
              'uaadb' => {
                  'db_scheme' => 'something',
              }
          }
      }
    }

    it 'matches' do
      expect(generated_script).to include("active_spring_profiles=something")
      expect(generated_script).to include("-Dspring.profiles.active=${active_spring_profiles}")
    end
  end

  context 'with postgres and ldap' do
    let(:properties) {
      {
          'properties' => {
              'uaadb' => {
                  'db_scheme' => 'postgres',
              },
              'uaa' => {
                  'ldap' => {
                      'enabled' => true
                  }
              }
          }
      }
    }

    it 'matches' do
      expect(generated_script).to include("active_spring_profiles=postgresql,ldap")
      expect(generated_script).to include("-Dspring.profiles.active=${active_spring_profiles}")
    end
  end
end