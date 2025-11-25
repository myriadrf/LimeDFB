# Copyright date and release version should be updated accordingly!

project = 'Lime Digital Function Blocks'
copyright = '2024-2025 Lime Microsystems'
author = 'Lime Microsystems'
release = 'latest'

# These are used for the "Edit on GitHub" links.
# github_repo_path should be set to the branch + path to the docs.
# E.g. 'master/docs/', 'main/docs/' or 'docs/docs/' etc.

github_repo = 'LimeDFB'
github_repo_path= 'main/docs/'

# The default language for syntax highlighting in code blocks.
# This can be overridden using the ".. code-block::" directive.
highlight_language = 'python'

# Intersphinx mapping
# To minimise build time only include projects that are referenced.
intersphinx_internal = [
    'ppsdo',
    'sdrgw',
]

intersphinx_external = [
#    'sphinx',
]

# Set to True if the project is archived.
archived = False

# When True internal intersphinx targets point at stage.myriadrf.org.
staging = True
