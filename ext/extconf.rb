require 'mkmf'

dirs = ENV['PATH'].split(':') + %w[
  /opt
  /opt/local
  /opt/local/mysql
  /opt/local/lib/mysql5
  /usr
  /usr/local
  /usr/local/mysql
  /usr/local/mysql-*
  /usr/local/lib/mysql5
].map{|dir| "#{dir}/bin" }

GLOB = "{#{dirs.join(',')}}/{mysql_config,mysql_config5}"

if /mswin32/ =~ RUBY_PLATFORM
  inc, lib = dir_config('mysql')
  exit 1 unless have_library("libmysql")
elsif mc = (with_config('mysql-config') || Dir[GLOB].first) then
  mc = Dir[GLOB].first if mc == true
  cflags = `#{mc} --cflags`.chomp
  exit 1 if $? != 0
  libs = `#{mc} --libs`.chomp
  exit 1 if $? != 0
  $CPPFLAGS += ' ' + cflags
  $libs = libs + " " + $libs
else
  inc, lib = dir_config('mysql', '/usr/local')
  libs = ['m', 'z', 'socket', 'nsl', 'mygcc']
  while not find_library('mysqlclient', 'mysql_query', lib, "#{lib}/mysql") do
    exit 1 if libs.empty?
    have_library(libs.shift)
  end
end

have_func('mysql_ssl_set')
have_func('rb_str_set_len')

if have_header('mysql.h') then
  src = "#include <errmsg.h>\n#include <mysqld_error.h>\n"
elsif have_header('mysql/mysql.h') then
  src = "#include <mysql/errmsg.h>\n#include <mysql/mysqld_error.h>\n"
else
  exit 1
end

# check for 1.9
if have_func('rb_thread_blocking_region') and have_macro('RUBY_UBF_IO', 'ruby.h')
  $CFLAGS += " -DHAVE_TBR "
  $CPPFLAGS << " -DHAVE_TBR "
end

# make mysql constant
File.open("conftest.c", "w") do |f|
  f.puts src
end
if defined? cpp_command then
  cpp = Config.expand(cpp_command(''))
else
  cpp = Config.expand sprintf(CPP, $CPPFLAGS, $CFLAGS, '')
end
if /mswin32/ =~ RUBY_PLATFORM && !/-E/.match(cpp)
  cpp << " -E"
end
unless system "#{cpp} > confout" then
  exit 1
end
File.unlink "conftest.c"

error_syms = []
IO.foreach('confout') do |l|
  next unless l =~ /errmsg\.h|mysqld_error\.h/
  fn = l.split(/\"/)[1]
  IO.foreach(fn) do |m|
    if m =~ /^#define\s+([CE]R_[0-9A-Z_]+)/ then
      error_syms << $1
    end
  end
end
File.unlink 'confout'
error_syms.uniq!

File.open('error_const.h', 'w') do |f|
  error_syms.each do |s|
    f.puts "    rb_define_mysql_const(#{s});"
  end
end

create_makefile("mysql")