# RJR Message
#
# Representations of json-rpc messages in accordance with the standard
#
# Copyright (C) 2012 Mohammed Morsi <mo@morsi.org>
# Licensed under the Apache License, Version 2.0

# establish client connection w/ specified args and invoke block w/ 
# newly created client, returning it after block terminates

require 'json'

module RJR

# Message sent from client to server to invoke a json-rpc method
class RequestMessage
  # Helper method to generate a random id
  def self.gen_uuid
    ["%02x"*4, "%02x"*2, "%02x"*2, "%02x"*2, "%02x"*6].join("-") %
        Array.new(16) {|x| rand(0xff) }
  end

  # Message string received from the source
  attr_accessor :json_message

  # Method source is invoking on the destination
  attr_accessor :jr_method

  # Arguments source is passing to destination method
  attr_accessor :jr_args

  # ID of the message in accordance w/ json-rpc specification
  attr_accessor :msg_id

  # Optional headers to add to json outside of standard json-rpc request
  attr_accessor :headers

  # RJR Request Message initializer
  #
  # This should be invoked with one of two argument sets. If creating a new message
  # to send to the server, specify :method, :args, and :headers to include in the message
  # (message id will be autogenerated). If handling an new request message sent from the
  # client, simply specify :message and optionally any additional headers (they will 
  # be merged with the headers contained in the message)
  #
  # @param [Hash] args options to set on request
  # @option args [String] :message json string received from sender
  # @option args [Hash] :headers optional headers to set in request and subsequent messages
  # @option args [String] :method method to invoke on server
  # @option args [Array<Object>] :args to pass to server method, all must be convertable to/from json
  def initialize(args = {})
    if args.has_key?(:message)
      begin
        request = JSON.parse(args[:message])
        @json_message = args[:message]
        @jr_method = request['method']
        @jr_args   = request['params']
        @msg_id    = request['id']
        @headers   = args.has_key?(:headers) ? {}.merge!(args[:headers]) : {}

        request.keys.select { |k|
          !['jsonrpc', 'id', 'method', 'params'].include?(k)
        }.each { |k| @headers[k] = request[k] }

      rescue Exception => e
        #puts "Exception Parsing Request #{e}"
        raise e
      end

    elsif args.has_key?(:method)
      @jr_method = args[:method]
      @jr_args   = args[:args]
      @headers   = args[:headers]
      @msg_id    = RequestMessage.gen_uuid

    end
  end

  # Class helper to determine if the specified string is a valid json-rpc
  # method request
  # @param [String] message string message to check
  # @return [true,false] indicating if message is request message
  def self.is_request_message?(message)
    begin
       # TODO log error
       parsed = JSON.parse(message)
       parsed.has_key?('method') && parsed.has_key?('id')
    rescue Exception => e
      false
    end
  end

  # Convert request message to string json format
  def to_s
    request = { 'jsonrpc' => '2.0',
                'method' => @jr_method,
                'params' => @jr_args }
    request['id'] = @msg_id unless @msg_id.nil?
    request.merge!(@headers) unless @headers.nil?
    request.to_json.to_s
  end

end

# Message sent from server to client in response to json-rpc request message
class ResponseMessage
  # Message string received from the source
  attr_accessor :json_message

  # ID of the message in accordance w/ json-rpc specification
  attr_accessor :msg_id

  # Result encapsulated in the response message
  # @see RJR::Result
  attr_accessor :result

  # Optional headers to add to json outside of standard json-rpc request
  attr_accessor :headers

  # ResponseMessage initializer
  #
  # This should be invoked with one of two argument sets. If creating a new message
  # to send to the client, specify :id, :result, and :headers to include in the message.
  # If handling an new request message sent from the client, simply specify :message
  # and optionally any additional headers (they will be merged with the headers contained
  # in the message)
  #
  # @param [Hash] args options to set on request
  # @option args [String] :message json string received from sender
  # @option args [Hash] :headers optional headers to set in request and subsequent messages
  # @option args [String] :id id to set in response message, should be same as that in received message
  # @option args [RJR::Result] :result result of json-rpc method invocation
  def initialize(args = {})
    if args.has_key?(:message)
      response = JSON.parse(args[:message])
      @json_message  = args[:message]
      @msg_id  = response['id']
      @result   = Result.new
      @result.success   = response.has_key?('result')
      @result.failed    = !response.has_key?('result')
      @headers   = args.has_key?(:headers) ? {}.merge!(args[:headers]) : {}

      if @result.success
        @result.result = response['result']

      elsif response.has_key?('error')
        @result.error_code = response['error']['code']
        @result.error_msg  = response['error']['message']
        @result.error_class = response['error']['class']  # TODO safely constantize this ?

      end

      response.keys.select { |k|
        !['jsonrpc', 'id', 'result', 'error'].include?(k)
      }.each { |k| @headers[k] = response[k] }

    elsif args.has_key?(:result)
      @msg_id  = args[:id]
      @result  = args[:result]
      @headers = args[:headers]

    #else
    #  raise ArgumentError, "must specify :message or :result"

    end

  end

  # Class helper to determine if the specified string is a valid json-rpc
  # method response
  # @param [String] message string message to check
  # @return [true,false] indicating if message is response message
  def self.is_response_message?(message)
    begin
      json = JSON.parse(message)
      json.has_key?('result') || json.has_key?('error')
    rescue Exception => e
      # TODO log error
      #puts e.to_s
      false
    end
  end

  # Convert request message to string json format
  def to_s
    s = ''
    if result.success
      s =    {'jsonrpc' => '2.0',
              'id'      => @msg_id,
              'result'  => @result.result}

    else
      s =    {'jsonrpc' => '2.0',
              'id'      => @msg_id,
              'error'   => { 'code'    => @result.error_code,
                             'message' => @result.error_msg,
                             'class'   => @result.error_class}}
    end

    s.merge! @headers unless headers.nil?
    return s.to_json.to_s
  end
end

# Message sent to a jsonrpc node to invoke a rpc method but
# indicate the result should _not_ be returned
class NotificationMessage
  # Message string received from the source
  attr_accessor :json_message

  # Method source is invoking on the destination
  attr_accessor :jr_method

  # Arguments source is passing to destination method
  attr_accessor :jr_args

  # Optional headers to add to json outside of standard json-rpc request
  attr_accessor :headers

  # RJR Notification Message initializer
  #
  # This should be invoked with one of two argument sets. If creating a new message
  # to send to the server, specify :method, :args, and :headers to include in the message
  # If handling an new request message sent from the client, simply specify :message and
  # optionally any additional headers (they will be merged with the headers contained in
  # the message)
  # 
  # No message id will be generated in accordance w/ the jsonrpc standard
  #
  # @param [Hash] args options to set on request
  # @option args [String] :message json string received from sender
  # @option args [Hash] :headers optional headers to set in request and subsequent messages
  # @option args [String] :method method to invoke on server
  # @option args [Array<Object>] :args to pass to server method, all must be convertable to/from json
  def initialize(args = {})
    if args.has_key?(:message)
      begin
        notification = JSON.parse(args[:message])
        @json_message = args[:message]
        @jr_method = notification['method']
        @jr_args   = notification['params']
        @headers   = args.has_key?(:headers) ? {}.merge!(args[:headers]) : {}

        notification.keys.select { |k|
          !['jsonrpc', 'method', 'params'].include?(k)
        }.each { |k| @headers[k] = notification[k] }

      rescue Exception => e
        #puts "Exception Parsing Notification #{e}"
        raise e
      end

    elsif args.has_key?(:method)
      @jr_method = args[:method]
      @jr_args   = args[:args]
      @headers   = args[:headers]

    end
  end

  # Class helper to determine if the specified string is a valid json-rpc
  # notification
  #
  # @param [String] message string message to check
  # @return [true,false] indicating if message is a notification message
  def self.is_notification_message?(message)
    begin
       # TODO log error
       parsed = JSON.parse(message)
       parsed.has_key?('method') && !parsed.has_key?('id')
    rescue Exception => e
      false
    end
  end

  # Convert notification message to string json format
  def to_s
    notification = { 'jsonrpc' => '2.0',
                     'method' => @jr_method,
                     'params' => @jr_args }
    notification.merge!(@headers) unless @headers.nil?
    notification.to_json.to_s
  end

end

# Helper utilities for messages
class MessageUtil
  # Retrieve and return a single json message from a data string.
  #
  # Returns the message and remaining portion of the data string,
  # if message is found, else nil
  #
  # XXX really don't like having to do this, but a quick solution
  # to the issue of multiple messages appearing in one tcp data packet.
  #
  # TODO efficiency can probably be optimized
  #   in the case closing '}' hasn't arrived yet
  def self.retrieve_json(data) 
    return nil if data.nil? || data.empty?
    start  = 0
    start += 1 until start == data.length || data[start] == '{'
    on = mi = 0 
    start.upto(data.length - 1).each { |i|
      if data[i] == '{'
        on += 1
      elsif data[i] == '}'
        on -= 1
      end

      if on == 0
        mi = i
        break
      end
    }
    
    return nil if mi == 0
    return data[start..mi], data[(mi+1)..-1]
  end

end

end
