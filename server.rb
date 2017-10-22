require 'sinatra'
require 'bunny'
require 'nexmo'
require 'json'

STDOUT.sync = true

MESSAGE_RECEIVED_EXCHANGE = 'vimmcvimface.received'
MESSAGE_PUBLISH_EXCHANGE = 'vimmcvimface.publish'

class QueueControl
  attr_accessor :conn

  def initialize(rmq_uri)
    @conn = Bunny.new(rmq_uri)
    connected = false
    until connected do
      begin
        @conn.start
        connected = true
      rescue
        puts "."
        sleep 1
      end
    end
  end

  def with_exchange(name)
    with_channel do |ch|
      x = ch.fanout(name)
      yield ch, x
    end
  end

  def with_queue(exchange_name, queue_name)
    with_exchange(exchange_name) do |ch, x|
      q = ch.queue(queue_name, :auto_delete => true).bind(x)
      yield ch, q
    end
  end

  def with_channel
    ch = conn.create_channel
    yield ch
  end
end

class Telephony
  attr_accessor :client, :number

  def initialize(key, secret, phone_number)
    @client = Nexmo::Client.new(key: key, secret: secret)
    @number = phone_number
  end

  def send_message(to, message)
    client.send_message(from: number, to: to, text: message)
  end
end

qc = QueueControl.new(ENV['RABBITMQ_URI'])
tele = Telephony.new(ENV['NEXMO_KEY'], ENV['NEXMO_SECRET'], ENV['PHONE_NUMBER'])

qc.with_queue(MESSAGE_PUBLISH_EXCHANGE, "") do |ch, q|
  q.subscribe do |delivery_info, properties, payload|
    puts "[#{q.name}] Received message: #{payload}"
    parsed = JSON.load(payload)
    tele.send_message(parsed['to'], parsed['message'])
  end
end

get '/' do
  "Hello world"
end

post '/incoming-sms' do
  puts "received sms #{params}"
  qc.with_exchange(MESSAGE_RECEIVED_EXCHANGE) do |ch, x|
    puts "[#{MESSAGE_RECEIVED_EXCHANGE}] Publishing message: #{JSON.dump(params)}"
    x.publish(JSON.dump(params))
  end
end

