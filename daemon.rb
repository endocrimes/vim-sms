require 'bunny'
require 'json'
require 'fileutils'

MESSAGE_RECEIVED_EXCHANGE = 'vimmcvimface.received'
MESSAGE_PUBLISH_EXCHANGE = 'vimmcvimface.publish'

class QueueControl
  attr_accessor :conn

  def initialize(rmq_uri)
    @conn = Bunny.new(rmq_uri)
    @conn.start
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

qc = QueueControl.new(ENV['RABBITMQ_URI'])

qc.with_queue(MESSAGE_RECEIVED_EXCHANGE, "") do |ch, q|
  puts "Subscribing to exchange: #{MESSAGE_RECEIVED_EXCHANGE}"
  q.subscribe do |delivery_info, properties, payload|
    puts "[#{q.name}] Received message: #{payload}"
    parsed = JSON.load(payload)
    path = "#{ENV['FILE_ROOT']}/#{parsed['msisdn']}/#{parsed['messageId']}.txt"
    puts path
    File.write(path, parsed['text'])
  end
end

loop do
  puts "Looking for globs:"
  Dir.glob("#{ENV['FILE_ROOT']}/*/new") do |glob|
    s = glob.split("/")
    to = s[s.size - 2]
    qc.with_exchange(MESSAGE_PUBLISH_EXCHANGE) do |ch, x|
      params = {to: to, message: File.read(glob)}
      puts "[#{MESSAGE_RECEIVED_EXCHANGE}] Publishing message: #{JSON.dump(params)}"
      x.publish(JSON.dump(params))
    end

    FileUtils.rm(glob)
  end

  sleep 10
end
