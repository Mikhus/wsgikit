from cherrypy import wsgiserver
import wsgikit,json

def application( environ, start_response):
	try :
		status = '200 OK'
		response_headers = [('Content-type','application/json')]
		
		r = wsgikit.HttpRequest(
			environ,
			max_uploaded_files = 2,
			max_filesize = 1024,
			max_content_length=512
		)
		
		if r.has_files():
			r.FileUploader.move_all( './uploads', True)
		
		rdict = r.to_dict()
		del rdict['SERVER']
		
		content = json.dumps( rdict)
	
	except wsgikit.HttpRequestError as e:
		status = '500 Internal Server Error'
		response_headers = [('Content-type','text/plain')]
		
		content = str(e)
	
	start_response( status, response_headers)
	
	return content

# run the server
server = wsgiserver.CherryPyWSGIServer(
	('0.0.0.0', 10888), application,
	server_name='localhost'
)

server.start()
