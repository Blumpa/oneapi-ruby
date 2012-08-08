require 'net/http'
require 'net/https'

require_relative 'objects'
require_relative 'models'

module OneApi

    class OneApiClient

        # If true -- an exception will be thrown on error, otherwise, you have 
        # to check the is_success and exception methods on resulting objects.
        attr_accessor :raise_exceptions

        def initialize(username, password, base_url=nil)
            @username = username
            @password = password
            if base_url
                @base_url = base_url
            else
                @base_url = 'https://api.parseco.com'
            end

            if @base_url[-1, 1] != '/'
                @base_url += '/'
            end

            @oneapi_authentication = nil
            @raise_exceptions = true
        end


        def login()
            params = {
                    'username' => @username,
                    'password' => @password,
            }

            is_success, result = self.execute_POST('/1/customerProfile/login', params)

            return self.fill_oneapi_authentication(result, is_success)
        end

        def get_or_create_client_correlator(client_correlator=None)
            if client_correlator
                return client_correlator
            end

            return Utils.get_random_alphanumeric_string()
        end

        def prepare_headers(request)
            request["User-Agent"] = "OneApi Ruby client" # TODO: Add version!
            if @oneapi_authentication and @oneapi_authentication.ibsso_token
                request['Authorization'] = "IBSSO #{@oneapi_authentication.ibsso_token}"
            end
        end

        def is_success(response)
            http_code = response.code.to_i
            is_success = 200 <= http_code && http_code < 300

            is_success
        end

        def urlencode(params)
            if not params
                return ''
            end
            if params.instance_of? String
                return URI.encode(params)
            end
            result = ''
            params.each_key do |key|
                if result
                    result += '&'
                end
                result += URI.encode(key.to_s) + '=' + URI.encode(params[key].to_s)
            end

            return '?' + result
        end

        def execute_GET(url, params)
            execute_request('GET', url, params)
        end

        def execute_POST(url, params)
            execute_request('POST', url, params)
        end

        def execute_request(http_method, url, params)
            rest_url = get_rest_url(url)
            uri = URI(rest_url)

            if http_method == 'GET'
                request = Net::HTTP::Get.new(uri.request_uri)
                uri.query = urlencode(params)
            elsif http_method == 'POST'
                request = Net::HTTP::Post.new(uri.request_uri)
            end

            http = Net::HTTP.new(uri.host, uri.port)

            use_ssl = rest_url.start_with? "https"
            if use_ssl
                http.use_ssl = true
                http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            end

            prepare_headers(request)
            request.set_form_data(params)
            response = http.request(request)

            return is_success(response), response.body
        end

        def get_rest_url(rest_path)
            if not rest_path
                return @base_url
            end

            if rest_path[0, 1] == '/'
                return @base_url + rest_path[1, rest_path.length]
            end

            @base_url + rest_path
        end

        def fill_oneapi_authentication(json, is_success)
            @oneapi_authentication = convert_from_json(OneApiAuthentication, json, !is_success)

            @oneapi_authentication.username = @username
            @oneapi_authentication.password = @password

            @oneapi_authentication.authenticated = @oneapi_authentication.ibsso_token ? @oneapi_authentication.ibsso_token.length > 0 : false

            @oneapi_authentication
        end

        def convert_from_json(classs, json, is_error)
            result = Conversions.from_json(classs, json, is_error)

            if @raise_exceptions and !result.is_success
                raise "#{result.exception.message_id}: #{result.exception.text} [#{result.exception.variables}]"
            end

            result
        end

    end

    class SmsClient < OneApiClient

        def initialize(username, password, base_url=nil)
            super(username, password, base_url)
        end

        def send_sms(sms)
            client_correlator = sms.client_correlator
            if not client_correlator
                client_correlator = Utils.get_random_alphanumeric_string()
            end

            params = {
                'senderAddress' => sms.sender_address,
                'address' => sms.address,
                'message' => sms.message,
                'clientCorrelator' => client_correlator,
                'senderName' => "tel:#{sms.sender_address}"
            }

            if sms.notify_url
                params['notifyURL'] = sms.notify_url
            end
            if sms.callback_data
                params['callbackData'] = sms.callback_data
            end

            is_success, result = self.execute_POST(
                    "/1/smsmessaging/outbound/#{sms.sender_address}/requests",
                    params
            )

            convert_from_json(ResourceReference, result, !is_success)
        end

        def query_delivery_status(client_correlator_or_resource_reference)
            if defined? client_correlator_or_resource_reference.client_correlator
                client_correlator = client_correlator_or_resource_reference.client_correlator
            else
                client_correlator = client_correlator_or_resource_reference
            end

            client_correlator = self.get_or_create_client_correlator(client_correlator)

            params = {
                'clientCorrelator' => client_correlator,
            }

            is_success, result = self.execute_GET(
                    "/1/smsmessaging/outbound/TODO/requests/#{client_correlator}/deliveryInfos",
                    params
            )

            return convert_from_json(DeliveryInfoList, result, !is_success)
        end

    end

end

