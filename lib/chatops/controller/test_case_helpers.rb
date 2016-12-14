module ChatOps::Controller::TestCaseHelpers

  class NoMatchingCommandRegex < StandardError ; end

  def chatops_auth!(user = "_", pass = ENV["CHATOPS_AUTH_TOKEN"])
    request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Basic.encode_credentials(user, pass)
  end

  def chatop(method, params = {})
    args = params.dup.symbolize_keys
    user = args.delete :user
    room_id = args.delete :room_id

    params = {
      :params => args,
      :room_id => room_id,
      :user => user
    }

    if Rails.version.slice(0).to_i >= 5
      post :execute_chatop, params: params.merge(chatop: method)
    else
      post :execute_chatop, params.merge(chatop: method)
    end
  end

  def chat(message, user, room_id = "123")
    get :list
    json_response = JSON.load(response.body)
    matchers = json_response["methods"].map { |name, metadata|
      metadata = metadata.dup
      metadata["name"] = name
      metadata["regex"] = Regexp.new("^#{metadata["regex"]}$", "i")
      metadata
    }

    named_params, command = extract_named_params(message)

    matcher = matchers.find { |matcher| matcher["regex"].match(command) }

    raise NoMatchingCommandRegex.new("No command matches '#{command}'") unless matcher

    match_data = matcher["regex"].match(command)
    jsonrpc_params = named_params.dup
    matcher["params"].each do |param|
      jsonrpc_params[param] = match_data[param.to_sym]
    end
    jsonrpc_params.merge!(user: user, room_id: room_id)
    chatop matcher["name"].to_sym, jsonrpc_params
  end

  def chatop_response
    json_response = JSON.load(response.body)
    if json_response["error"].present?
      raise "There was an error instead of an expected successful response: #{json_response["error"]}"
    end
    json_response["result"]
  end

  def chatop_error
    json_response = JSON.load(response.body)
    json_response["error"]["message"]
  end

  def extract_named_params(command_string)
    params = {}

    while last_index = command_string.rindex(" --")
      arg = command_string[last_index..-1]
      matches = arg.match(/ --(\S+)(.*)/)
      params[matches[1]] = matches[2].strip
      params[matches[1]] = "true" unless params[matches[1]].present?
      command_string = command_string.slice(0, last_index)
    end

    command_string = command_string.strip
    [params, command_string]
  end
end
