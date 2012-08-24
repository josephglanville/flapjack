#!/usr/bin/env ruby

require 'action_view'
require 'haml/template'
require 'haml/template/plugin' # haml templates won't work without this

require 'flapjack/data/entity_check'
require 'flapjack/notification/common'

# TODO define these somewhere more central
ActionMailer::Base.raise_delivery_errors = true
ActionMailer::Base.view_paths = File.dirname(__FILE__)
ActionMailer::Base.delivery_method = :smtp
ActionMailer::Base.smtp_settings = { :address => "127.0.0.1",
                                     :port => 25,
                                     :enable_starttls_auto => false }

module Flapjack
  module Notification

    class Email
      extend Flapjack::Notification::Common

      def self.dispatch(notification, opts = {})
        notification_type  = notification['notification_type']
        contact_first_name = notification['contact_first_name']
        contact_last_name  = notification['contact_last_name']
        state              = notification['state']
        summary            = notification['summary']
        time               = notification['time']
        entity, check      = notification['event_id'].split(':')
        entity_check = Flapjack::Data::EntityCheck.new(:entity => entity,
          :check => check, :redis => @persistence)

        headline_map = {'problem'         => 'Problem: ',
                        'recovery'        => 'Recovery: ',
                        'acknowledgement' => 'Acknowledgement: ',
                        'unknown'         => ''
                       }

        headline = headline_map[notification_type] || ''

        subject = "#{headline}'#{check}' on #{entity}"
        subject += " is #{state.upcase}" unless notification_type == 'acknowledgement'

        notification['subject'] = subject
        opts[:logger].debug "Flapjack::Notification::Email#dispatch is calling Flapjack::Notification::Mailer.sender, notification_id: #{notification['id']}"
        sender_opts = {:logger => opts[:logger],
                       :in_scheduled_maintenance   => entity_check.in_scheduled_maintenance?,
                       :in_unscheduled_maintenance => entity_check.in_unscheduled_maintenance?
                      }
        Flapjack::Notification::Mailer.sender(notification, sender_opts).deliver
      end

    end

    # FIXME: move this to a separate file
    class Mailer < ActionMailer::Base

      self.mailer_name = 'flapjack_mailer'

      def sender(notification, opts)
        logger = opts[:logger]

        # FIXME: use socket and gethostname instead of shelling out
        fqdn     = `/bin/hostname -f`.chomp
        from     = "flapjack@#{fqdn}"
        logger.debug("flapjack_mailer: set from to #{from}")
        reply_to = from

        to                  = notification['address']
        subject             = notification['subject']

        logger.debug("Flapjack::Notification::Mailer #{notification['id']} to: #{to} subject: #{subject}")

        @notification_type  = notification['notification_type']
        @contact_first_name = notification['contact_first_name']
        @contact_last_name  = notification['contact_last_name']
        @state              = notification['state']
        @summary            = notification['summary']
        @time               = notification['time']
        @entity, @check     = notification['event_id'].split(':')
        @in_unscheduled_maintenance = opts[:in_unscheduled_maintenance]
        @in_scheduled_maintenance   = opts[:in_scheduled_maintenance]

        mail(:subject  => subject,
             :from     => from,
             :to       => to,
             :reply_to => reply_to) do |format|
          format.text
          format.html
        end
      end

    end
  end
end

