from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

ext_modules = [
	Extension( "wsgikit", ["wsgikit/wsgikit.pyx"])
]

setup(
	name           = "wsgikit",
	version        = "0.2a",
	description    = "Python tools for WSGI applications",
	author         = "Mykhailo Stadnyk",
	author_email   = "mikhus@gmail.com",
	url            = "https://github.com/Mikhus/wsgikit",
	download_url   = "https://github.com/Mikhus/wsgikit/zipball/master",
	keywords       = ["HTTP request", "file upload"],
	platforms      = ['OS Independent'],
	license        = 'MIT License',
	ext_modules    = cythonize(ext_modules),
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
