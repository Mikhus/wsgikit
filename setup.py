from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize
import re

module_src = "wsgikit/wsgikit.pyx"

def version():
	fp = open( module_src)
	version = re.search( "^__version__\s*=\s*['\"]([^'\"]*)['\"]", fp.read(), re.M).group(1)
	fp.close()
	return version

ext_modules = [
	Extension( "wsgikit", [module_src])
]

setup(
	name           = "wsgikit",
	version        = version(),
	description    = "Python tools for WSGI applications",
	author         = "Mykhailo Stadnyk",
	author_email   = "mikhus@gmail.com",
	url            = "https://github.com/Mikhus/wsgikit",
	download_url   = "https://github.com/Mikhus/wsgikit/zipball/master",
	keywords       = ["HTTP request", "file upload"],
	platforms      = ['OS Independent'],
	license        = 'MIT License',
	ext_modules    = cythonize( ext_modules),
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
