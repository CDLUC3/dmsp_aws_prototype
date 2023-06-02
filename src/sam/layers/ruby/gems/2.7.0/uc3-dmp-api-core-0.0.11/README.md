# Uc3DmpApiCore

Basic helper classes used by the DMPTool Lambda functions.

- LogWriter: Helper for logging messages and errors to CloudWatch
- Notifier: Helper for sending emails via SNS and sending events to EventBridge
- Paginator: Helper for paginating search results and building the pagination links for the response
- Responder: Helper that formats API responses in a standardized way
- SsmReader: Helper that fetches values from the SSM parameter store
