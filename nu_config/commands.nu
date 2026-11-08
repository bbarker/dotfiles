
def create-title-filename [title:string] {
  let cleaned = $title | str trim | str downcase 
    | str replace -a -r '[^\w\s]' ''
    | str replace -a -r '[\t\n\r]+' ' '
    | str replace -a -r '\s+' '_'
  [$cleaned ".pdf"] | str join 
}

def rename-file-with-title [file:path, title:string] {
  let new_filename = create-title-filename $title
  let dir = $file | path dirname
  let new_path = ($dir | path join $new_filename)
  mv $file $new_path
  echo $"File moved to: ($new_path)"
}

# Load the variables a bash-sourceable file (a .env) sets into this shell.
# The source_nu script in ~/.local/bin does the reading; a script cannot set
# its caller's environment, so this wrapper does the loading.
def --env source_nu [file: path] {
  ^source_nu $file | from json | load-env
}
