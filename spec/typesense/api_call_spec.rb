require_relative '../spec_helper'
require_relative 'shared_configuration_context'

describe Typesense::ApiCall do
  include_context 'Typesense configuration'

  shared_examples 'General error handling' do |method|
    {
        400 => Typesense::Error::RequestMalformed,
        401 => Typesense::Error::RequestUnauthorized,
        404 => Typesense::Error::ObjectNotFound,
        409 => Typesense::Error::ObjectAlreadyExists,
        422 => Typesense::Error::ObjectUnprocessable,
        500 => Typesense::Error::ServerError,
        300 => Typesense::Error
    }.each do |response_code, error|
      it "throws #{error} for a #{response_code} response" do
        stub_request(:any, Typesense::ApiCall.send(:uri_for, '/')).
            to_return(status:  response_code,
                      body:    JSON.dump({ 'message' => 'Error Message' }),
                      headers: { 'Content-Type' => 'application/json' }
            )

        stub_request(:any, Typesense::ApiCall.send(:uri_for, '/', :read_replica, 0)).
            to_return(status:  response_code,
                      body:    JSON.dump({ 'message' => 'Error Message' }),
                      headers: { 'Content-Type' => 'application/json' }
            )

        stub_request(:any, Typesense::ApiCall.send(:uri_for, '/', :read_replica, 1)).
            to_return(status:  response_code,
                      body:    JSON.dump({ 'message' => 'Error Message' }),
                      headers: { 'Content-Type' => 'application/json' }
            )

        expect {
          subject.send(method, '')
        }.to raise_error error
      end
    end

    it 'throws an Error if no config values are not set' do
      Typesense.configuration = nil

      expect {
        subject.send(method, '')
      }.to raise_error Typesense::Error::MissingConfiguration
    end

    it 'throws an Error if the master_node config is not set' do
      Typesense.configuration.master_node = nil

      expect {
        subject.send(method, '')
      }.to raise_error Typesense::Error::MissingConfiguration
    end


    %i(protocol host port api_key).each do |config_value|
      it "throws an Error if master config value for #{config_value} is nil" do
        Typesense.configuration.master_node.send(:[]=, config_value.to_sym, nil)

        expect {
          subject.send(method, '')
        }.to raise_error Typesense::Error::MissingConfiguration
      end

      it "throws an Error if read_replica configs for #{config_value} is missing values" do
        Typesense.configuration.read_replica_nodes[0].send(:[]=, config_value.to_sym, nil)

        expect {
          subject.send(method, '')
        }.to raise_error Typesense::Error::MissingConfiguration
      end
    end
  end

  shared_examples 'Read Replica selection for write operations' do |method|
    def common_expectations(method, master_node_stub, exception)
      expect {
        subject.send(method, '')
      }.to raise_error exception

      expect(master_node_stub).to have_been_requested

      expect(a_request(:any, Typesense::ApiCall.send(:uri_for, '/', :read_replica))).not_to have_been_made
    end

    it 'does not use any read replicas and fails immediately when there is a server error' do
      master_node_stub = stub_request(:any, Typesense::ApiCall.send(:uri_for, '/', :master)).
          to_return(status:  500,
                    body:    JSON.dump({ 'message' => 'Error Message' }),
                    headers: { 'Content-Type' => 'application/json' }
          )

      common_expectations(method, master_node_stub, Typesense::Error::ServerError)
    end

    it 'does not use any read replicas and fails immediately when there is a connection timeout' do
      master_node_stub = stub_request(:any, Typesense::ApiCall.send(:uri_for, '/', :master)).to_timeout

      common_expectations(method, master_node_stub, Net::OpenTimeout)
    end
  end

  shared_examples 'Read Replica selection for read operations' do |method|
    def common_expectations(method, master_node_stub, read_replica_0_node_stub, read_replica_1_node_stub)
      expect {
        subject.send(method, '')
      }.to_not raise_error

      expect(master_node_stub).to have_been_requested
      expect(read_replica_0_node_stub).to have_been_requested
      expect(read_replica_1_node_stub).to have_been_requested
    end

    it 'selects the next available read replica when there is a server error' do
      master_node_stub = stub_request(:any, Typesense::ApiCall.send(:uri_for, '/', :master)).
          to_return(status:  500,
                    body:    JSON.dump({ 'message' => 'Error Message' }),
                    headers: { 'Content-Type' => 'application/json' }
          )

      read_replica_0_node_stub = stub_request(:any, Typesense::ApiCall.send(:uri_for, '/', :read_replica, 0)).
          to_return(status:  500,
                    body:    JSON.dump({ 'message' => 'Error Message' }),
                    headers: { 'Content-Type' => 'application/json' }
          )

      read_replica_1_node_stub = stub_request(:any, Typesense::ApiCall.send(:uri_for, '/', :read_replica, 1)).
          to_return(status:  200,
                    body:    JSON.dump({ 'message' => 'Success' }),
                    headers: { 'Content-Type' => 'application/json' }
          )

      common_expectations(method, master_node_stub, read_replica_0_node_stub, read_replica_1_node_stub)
    end

    it 'selects the next available read replica when there is a connection timeout' do
      master_node_stub         = stub_request(:any, Typesense::ApiCall.send(:uri_for, '/')).to_timeout
      read_replica_0_node_stub = stub_request(:any, Typesense::ApiCall.send(:uri_for, '/', :read_replica, 0)).to_timeout
      read_replica_1_node_stub = stub_request(:any, Typesense::ApiCall.send(:uri_for, '/', :read_replica, 1)).
          to_return(status:  200,
                    body:    JSON.dump({ 'message' => 'Success' }),
                    headers: { 'Content-Type' => 'application/json' }
          )

      common_expectations(method, master_node_stub, read_replica_0_node_stub, read_replica_1_node_stub)
    end
  end

  describe '#post' do
    include_examples 'General error handling', :post
    include_examples 'Read Replica selection for write operations', :post
  end

  describe '#get' do
    include_examples 'General error handling', :get
    include_examples 'Read Replica selection for read operations', :get
  end

  describe '#get_unparsed_response' do
    include_examples 'General error handling', :get_unparsed_response
    include_examples 'Read Replica selection for read operations', :get_unparsed_response
  end

  describe '#delete' do
    include_examples 'General error handling', :delete
    include_examples 'Read Replica selection for write operations', :delete
  end
end

