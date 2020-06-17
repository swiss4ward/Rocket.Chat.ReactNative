import CoreLocation
import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    var retryCount = 0
    var retryTimeout = [1.0, 3.0, 5.0, 10.0]

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestAttemptContent = bestAttemptContent {
            let suiteName = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as! String
            let userDefaults = UserDefaults(suiteName: suiteName)

            let ejson = bestAttemptContent.userInfo["ejson"] as! String
          
            if let data = ejson.data(using: .utf8) {
              let json = try? (JSONSerialization.jsonObject(with: data) as! [String: Any])
              if let json = json {
                  let host = json["host"] as! String
                  let msgId = json["messageId"] as! String
                  
                  let userId = userDefaults?.string(forKey: "reactnativemeteor_usertoken-\(host)")! ?? ""
                  let token = userDefaults?.string(forKey: "reactnativemeteor_usertoken-\(userId)")! ?? ""

                  var urlComponents = URLComponents(string: "\(host)/api/v1/chat.getMessage")!
                  let queryItems = [URLQueryItem(name: "msgId", value: msgId)]
                  urlComponents.queryItems = queryItems
                  
                  var request = URLRequest(url: urlComponents.url!)
                  request.httpMethod = "GET"
                  request.addValue(userId, forHTTPHeaderField: "x-user-id")
                  request.addValue(token, forHTTPHeaderField: "x-auth-token")

                  runRequest(request: request, bestAttemptContent: bestAttemptContent, contentHandler: contentHandler)
              }
            }
        }
    }
  
    func runRequest(request: URLRequest, bestAttemptContent: UNMutableNotificationContent, contentHandler: @escaping (UNNotificationContent) -> Void) {
        let task = URLSession.shared.dataTask(with: request) {(data, response, error) in

        func retryRequest() {
          // if we can try again
          if self.retryCount < self.retryTimeout.count {
            // Try again after X seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + self.retryTimeout[self.retryCount], execute: {
              self.runRequest(request: request, bestAttemptContent: bestAttemptContent, contentHandler: contentHandler)
              self.retryCount += 1;
            })
          }
        }

        // If some error happened
        if error != nil {
          retryRequest()

        // Check if the request did successfully
        } else if let response = response as? HTTPURLResponse {
            // if it not was successfully
            if response.statusCode != 200 {
              retryRequest()

            // If the response status is 200
            } else {
                // Process data
                if let data = data {
                    // Parse data of response
                    let json = try? (JSONSerialization.jsonObject(with: data) as! [String: Any])
                    if let json = json {
                      // Message
                      if let content = json["message"] as? [String: Any] {
                          // Message -> Msg
                          bestAttemptContent.body = content["msg"] as! String
                        
                          // Message -> U -> Username
                          if let user = content["u"] as? [String: Any] {
                              bestAttemptContent.title = user["username"] as! String
                          }
                      }
                    }
                    // Show notification with the content modified
                    contentHandler(bestAttemptContent)
                }
            }
        }
      }

      task.resume()
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}