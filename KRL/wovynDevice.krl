ruleset io.picolabs.wovyn_device {
  meta {

    name "wovyn_device"
    author "PJW"
    //description "General rules for wovyn system devices"

    //use module wrangler
    use module Subscriptions

    logging on

    shares thresholds, __testing
    provides thresholds
  }

  global {

    __testing = { "queries": [ { "name": "__testing" } ],
                  "events": [ { "domain": "wovyn", "type": "new_threshold",
                                "attrs": [ "threshold_type", "upper_limit", "lower_limit" ] } ] }
    //Manifold Discovery Components
    app = {"name":"journalling","version":"0.0"/* img: , pre: , ..*/};
    bindings = function(){
      {
        "chartType": "LineChart",
        "rows": getRows(),
        "columns": getColumns(),
        "width": "100%",
        "height": "100px",
        "options": getOptions()
      };
    }

    getRows = function(){
      [
        [1, 1],
        [2, 2],
        [3, 3],
        [4, 5],
        [5, 6],
        [8, 9]
      ]
    }

    getColumns = function(){
      [
        {
          "label":"Time",
          "type":"number",
          "p":{}
        },
        {
          "label":"Weight",
          "type":"number"
        }
      ]
    }

    getOptions = function(){
      {
        "title": "Last 10 Temp Readings",
        "hAxis": { "title": "Time" },
        "vAxis": { "title": "Degrees ℉" },
        "legend": "none"
      }
    }



    // public
    thresholds = function(threshold_type) {
      threshold_type.isnull() => ent:thresholds
                               | ent:thresholds{threshold_type}.defaultsTo({})
    }

    //private
    event_map = {
      "new_temperature_reading" : "temperature",
      "new_humidity_reading" : "humidity",
      "new_pressure_reading" : "pressure"
    };

    reading_map = {
      "temperature": "temperatureF",
      "humidity": "humidity",
      "pressure": "pressure"
    };

    Ecis = function () {
      return = Subscriptions:subscriptions(["attributes","subscriber_role"],"receive_temp").klog("subscriptions:   ");
      raw_subs = return;//{"subscriptions"}; // array of subs
      ecis = raw_subs.map(function( subs ){
        r = subs.values().klog("subs.values(): ");
        v = r[0].klog("subscription we want");
        v.attributes.outbound_eci
        });
      ecis.klog("ecis: ")
    };

    collectionSubscriptions = function () {
        return = Subscriptions:subscriptions("subscriber_role","receive_temp");
        raw_subs = return{"subscriptions"}; // array of subs
        //subs = raw_subs[0];
        raw_subs.klog("Subscriptions: ")
      };
  }//end global


  rule discovery { select when manifold apps send_directive("app discovered...", {"app": app, "rid": meta:rid, "bindings": bindings()} ); }


  // rule to save thresholds
  rule save_threshold {
    select when wovyn new_threshold
    pre {
      threshold_type = event:attr("threshold_type");
      threshold_value = {"limits": {"upper": event:attr("upper_limit"),
                                    "lower": event:attr("lower_limit")
           }};
    }
    if(not threshold_type.isnull()) then noop();
    fired {
      null.klog(<<Setting threshold value for #{threshold_type}>>);
      ent:thresholds := ent:thresholds.defaultsTo({}).put([threshold_type], threshold_value)
    }
  }

  rule check_threshold {
    select when wovyn new_temperature_reading
             or wovyn new_humidity_reading
             or wovyn new_pressure_reading
    foreach event:attr("readings").klog("The readings: ") setting (reading)
      pre {
        event_type = event:type().klog("Event type: ");

        // thresholds
        threshold_type = event_map{event_type}.klog("threshold_type");
        threshold_map = thresholds(threshold_type).klog("Thresholds: ");
        lower_threshold = threshold_map{["limits","lower"]}.klog("Lower threshold: ");
        upper_threshold = threshold_map{["limits","upper"]};

        // sensor readings
        data = reading.klog(<<Reading from #{threshold_type}: >>);
        reading_value = data{reading_map{threshold_type}}.klog(<<Reading value for #{threshold_type}: >>);
        sensor_name = data{"name"}.klog("Name of sensor: ");

        // decide
        under = reading_value < lower_threshold;
        over = upper_threshold < reading_value;
        msg = under => <<#{threshold_type} is under threshold of #{lower_threshold}>>
              | over  => <<#{threshold_type} is over threshold of #{upper_threshold}>>
              |          "";
      }
      if(  under || over ) then noop();
      fired {
        raise wovyn event "threshold_violation"
          attributes { "reading": reading.encode(),
                       "threshold": under => lower_threshold | upper_threshold,
                       "threshold_bound": under => "lower" | "upper"
                       // "message": <<threshold violation: #{msg} for #{sensor_name}>>
                     }
      }
  }


  // route events to all collections I'm a member of
  // change eventex to expand routed events.
  rule route_to_collections {
    select when wovyn threshold_violation
             or wovyn battery_level_low
    foreach Ecis() setting (eci)
      pre {
      }
      event:send({"eci": eci,"eid" : random:integer(100,2000) , "domain": "wovyn", "type": event:type(), "attrs": event:attrs()})
  }


  rule auto_approve_pending_subscriptions {
    select when wrangler inbound_pending_subscription_added
           //name_space re/wovyn-meta/gi
    pre{
      attributes = event:attrs().klog("subcription attributes :");
      subscriptions = Subscriptions:getSubscriptions().klog("Subscriptions:subscriptions(): ")
                        {"subscriptions"}
                        .klog(">>> current subscriptions >>>>")
      ;
      declared_relationship = "device_collection";
      relationship = event:attr("relationship").klog(">>> subscription relationship >>>>");
    }

    if ( not relationship like declared_relationship
      || subscriptions.length() == 0
       ) then // only auto approve the first subscription request
       noop();
    fired {
       null.klog(<< auto approving subscription: #{relationship}>>);
       raise wrangler event "pending_subscription_approval"
          attributes attributes;
    }
  }


}
