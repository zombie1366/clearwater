require "clearwater/router/route_collection"

module Clearwater
  class Router
    attr_reader :window, :location, :history
    attr_accessor :application

    def initialize options={}, &block
      if RUBY_ENGINE == 'opal'
        @window   = options.fetch(:window)   { Bowser.window  }
        @location = options.fetch(:location) { window.location }
        @history  = options.fetch(:history)  { window.history }
      else
        @location = options.fetch(:location)
      end
      @routes   = RouteCollection.new(self)
      @application = options[:application]

      add_routes(&block) if block_given?
    end

    def add_routes &block
      @routes.instance_exec(&block)
    end

    def routes_for_path path
      parts = get_path_parts(path)
      @routes[parts]
    end

    def canonical_path_for_path path
      routes_for_path(path).map { |r|
        namespace = r.namespace
        "#{"/#{namespace}" if namespace}/#{r.key}"
      }.join
    end

    def targets_for_path path
      routes_for_path(path).map(&:target)
    end

    def params path=current_path
      path_parts = get_path_parts(path)
      canonical_parts = get_path_parts(canonical_path_for_path(path))

      canonical_parts.each_with_index.reduce({}) { |params, (part, index)|
        if part.start_with? ":"
          param = part[1..-1]
          params[param] = path_parts[index]
        end

        params
      }
    end

    def canonical_path
    end

    def nested_routes
      @routes
    end

    def current_path
      location.path
    end

    def self.current_path
      location.path
    end

    def current_url
      location.href
    end

    def self.current_url
      location.href
    end

    def self.location
      Bowser.window.location
    end

    def navigate_to path
      old_path = current_path
      history.push path
      set_outlets
      trigger_routing_callbacks path: path, previous_path: old_path
      render_application
    end

    def self.navigate_to path
      old_path = current_path
      Bowser.window.history.push path
      Clearwater::Application::AppRegistry.each do |app|
        app.router.trigger_routing_callbacks(
          path: path,
          previous_path: old_path,
        )
      end
      render_all_apps
    end

    def navigate_to_remote path
      location.href = path
    end

    def back
      history.back
    end

    def trigger_routing_callbacks(path:, previous_path:)
      targets = targets_for_path(path)
      old_targets = targets_for_path(previous_path)
      routes = routes_for_path(path)
      old_params = params(previous_path)
      new_params = params(path)

      navigating_from = old_targets - targets
      navigating_to = targets - old_targets

      navigating_from.each do |target|
        if target.respond_to? :on_route_from
          target.on_route_from
        end
      end

      navigating_to.each do |target|
        if target.respond_to? :on_route_to
          target.on_route_to
        end
      end

      changed_dynamic_segments = new_params.select { |k, v| old_params[k] != v }
      changed_dynamic_targets = changed_dynamic_segments.each_key.map do |key|
        segment = ":#{key}"
        route = routes.find { |route| route.key == segment }.target
      end

      # Don't process these again
      changed_dynamic_targets -= navigating_from
      changed_dynamic_targets -= navigating_to

      changed_dynamic_targets.each do |target|
        target.on_route_from if target.respond_to? :on_route_from
        target.on_route_to if target.respond_to? :on_route_to
      end
    end

    def set_outlets targets=targets_for_path(current_path)
      if targets.any?
        (targets.count).times do |index|
          targets[index].outlet = targets[index + 1]
        end

        application && application.component.outlet = targets.first
      else
        application && application.component.outlet = nil
      end
    end

    private

    def get_path_parts path
      path.split("/").reject(&:empty?)
    end

    def render_application
      if application && application.component
        application.component.call
      end
    end

    def self.render_all_apps
      Clearwater::Application.render
    end
  end
end
