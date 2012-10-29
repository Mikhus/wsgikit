from distutils.core import setup
from distutils.extension import Extension
from wsgikit import __version__
try :
	from Cython.Distutils import build_ext
except ImportError:
	print("""You need to install Cython to build wsgikit extension.
To install Cython, please, use:

 > pip install cython

or

 > easy_install cython

or you can download and install it manually
from http://cython.org/#download
""")
	exit(1)

setup(
	name           = "wsgikit",
	version        = __version__,
	description    = "Python tools for WSGI applications",
	author         = "Mykhailo Stadnyk",
	author_email   = "mikhus@gmail.com",
	url            = "https://github.com/Mikhus/wsgikit",
	download_url   = "https://github.com/Mikhus/wsgikit/zipball/master",
	keywords       = ["HTTP request", "file upload"],
	platforms      = ['OS Independent'],
	license        = 'MIT License',
	cmdclass       = {'build_ext': build_ext},
	packages       = ['wsgikit'],
	ext_modules    = [Extension("wsgikit", ["wsgikit/wsgikit.pyx"])],
	classifiers    = [
		'Development Status :: 4 - Beta',
		'Environment :: Other Environment',
		'Intended Audience :: Developers',
		'License :: OSI Approved :: MIT License',
		'Natural Language :: English',
		'Operating System :: OS Independent',
		'Programming Language :: Python :: 2',
		'Programming Language :: Python :: 3',
		'Topic :: Software Development :: Libraries :: Python Modules',
	],
	long_description = """\
Python tools for WSGI applications
-------------------------------------

Fast HTTP request parsing, PHP-like params representation,
file upload handling, HTTP requests security, etc.
"""
)
