# ------------------------------------------------------------------
# Petal - Perl Template Attribute Language
# ------------------------------------------------------------------
# Author: Jean-Michel Hiver
# Description: Front-end for all Petal templating functionality
# ------------------------------------------------------------------
package Petal;
use Petal::Hash;
use Petal::Cache::Disk;
use Petal::Cache::Memory;
use Petal::Parser::XMLWrapper;
use Petal::Parser::HTMLWrapper;
use Petal::Canonicalizer::XML;
use Petal::Canonicalizer::XHTML;
use Petal::Functions;
use File::Spec;
use strict;
use warnings;
use Carp;
use Safe;
use Data::Dumper;


# these are used as local variables when the XML::Parser
# is crunching templates...
use vars qw /@tokens @nodeStack/;


# Encode / Decode info...
our $DECODE_CHARSET = undef;
our $ENCODE_CHARSET = undef;


# Prints as much info as possible when this is enabled.
our $DEBUG_DUMP = 1;


# Warn about uninitialised values in the template?
our $WARN_UNINIT = 0;


# What do we use to parse input?
our $INPUT  = 'XML';
our $INPUTS = {
    'XML'   => 'Petal::Parser::XMLWrapper',
    'HTML'  => 'Petal::Parser::HTMLWrapper',
    'XHTML' => 'Petal::Parser::HTMLWrapper',
};


# What do we use to format output?
our $OUTPUT  = 'XML';
our $OUTPUTS = {
    'XML'   => 'Petal::Canonicalizer::XML',
    'HTML'  => 'Petal::Canonicalizer::XHTML',
    'XHTML' => 'Petal::Canonicalizer::XHTML',
};


# makes taint mode happy if set to 1
our $TAINT = undef;


# don't confess() errors if we access an undefined template variable
our $ERROR_ON_UNDEF_VAR = 1;


# where are our templates supposed to be?
our @BASE_DIR = ('.');
our $BASE_DIR = undef; # for backwards compatibility...


# vroom!
our $DISK_CACHE = 1;


# vroom vroom!
our $MEMORY_CACHE = 1;


# prevents infinites includes...
our $MAX_INCLUDES = 30;
our $CURRENT_INCLUDES = 0;


# this is for CPAN
our $VERSION = '1.01';


# The CodeGenerator class backend to use.
# Change this only if you know what you're doing.
our $CodeGenerator = 'Petal::CodeGenerator';
our $CodeGeneratorLoaded = 0;

# Default language for multi-language mode.
# Change if you feel that English isn't a fair default.
our $LANGUAGE = 'en';


# this is for XML namespace support. Can't touch this :-)
our $NS = 'petal';
our $NS_URI = 'http://purl.org/petal/1.0/';

our $XI_NS = 'xi';
our $XI_NS_URI = 'http://www.w3.org/2001/XInclude';


# Displays the canonical template for template.xml.
# You can set $INPUT using by setting the PETAL_INPUT environment variable.
# You can set $OUTPUT using by setting the PETAL_OUTPUT environment variable.
sub main::canonical
{
    my $file = shift (@ARGV);
    local $Petal::DISK_CACHE = 0;
    local $Petal::MEMORY_CACHE = 0;
    local $Petal::INPUT  = $ENV{PETAL_INPUT}  || 'XML';
    local $Petal::OUTPUT = $ENV{PETAL_OUTPUT} || 'XHTML';
    print ${Petal->new ($file)->_canonicalize()};
}


# Displays the perl code for template.xml.
# You can set $INPUT using by setting the PETAL_INPUT environment variable.
# You can set $OUTPUT using by setting the PETAL_OUTPUT environment variable.
sub main::code
{
    my $file = shift (@ARGV);
    local $Petal::DISK_CACHE = 0;
    local $Petal::MEMORY_CACHE = 0;
    print Petal->new ($file)->_code_disk_cached;
}


# Displays the perl code for template.xml, with line numbers.
# You can set $INPUT using by setting the PETAL_INPUT environment variable.
# You can set $OUTPUT using by setting the PETAL_OUTPUT environment variable.
sub main::lcode
{
    my $file = shift (@ARGV);
    local $Petal::DISK_CACHE = 0;
    local $Petal::MEMORY_CACHE = 0;
    print Petal->new ($file)->_code_with_line_numbers;
}

sub load_code_generator
{
	if (not $CodeGeneratorLoaded)
	{
	    eval "require $CodeGenerator";
	    confess "Failed to load $CodeGenerator, $@" if $@;
	    $CodeGeneratorLoaded = 1;
	}
}

# Instanciates a new Petal object.
sub new
{
    my $class = shift;
    $class = ref $class || $class;
    unshift (@_, 'file') if (@_ == 1);
    my $self = bless { @_ }, $class;
    $self->_initialize();
    
    return $self;
}


# (multi language mode)
# if the language has been specified, let's try to
# find which template we can use.
sub _initialize
{
    my $self = shift;
    my $lang = $self->language() || return;
    
    my @dirs = $self->base_dir();
    @dirs = map { File::Spec->canonpath ("$_/$self->{file}") } @dirs;
    
    $self->{file} =~ s/\/$//;
    my $filename = Petal::Functions::find_filename ($lang, @dirs);
    $self->{file} .= "/$filename" if ($filename);
}


# (multi language mode)
# returns the current preferred language.
sub language
{
    my $self = shift;
    return $self->{language} || $self->{lang};
}


sub default_language   { exists $_[0]->{default_language}   ? $_[0]->{default_language}   : $LANGUAGE           }
sub input              { exists $_[0]->{input}              ? $_[0]->{input}              : $INPUT              }
sub output             { exists $_[0]->{output}             ? $_[0]->{output}             : $OUTPUT             }
sub taint              { exists $_[0]->{taint}              ? $_[0]->{taint}              : $TAINT              }
sub error_on_undef_var { exists $_[0]->{error_on_undef_var} ? $_[0]->{error_on_undef_var} : $ERROR_ON_UNDEF_VAR }
sub disk_cache         { exists $_[0]->{disk_cache}         ? $_[0]->{disk_cache}         : $DISK_CACHE         }
sub memory_cache       { exists $_[0]->{memory_cache}       ? $_[0]->{memory_cache}       : $MEMORY_CACHE       }
sub max_includes       { exists $_[0]->{max_includes}       ? $_[0]->{max_includes}       : $MAX_INCLUDES       }


sub base_dir
{
    my $self = shift;
    return map { defined $_ ? $_ : () } $self->_base_dir();
}


sub _base_dir
{
    my $self = shift;
    if (exists $self->{base_dir})
    {
	my $base_dir = $self->{base_dir};
	if (ref $base_dir) { return @{$base_dir} }
	else
	{
	    die '\$self->{base_dir} is not defined' unless (defined $base_dir);
	    return $base_dir;
	}
    }
    else
    {
	if (defined $BASE_DIR) { return ( $BASE_DIR, @BASE_DIR ) }
	else                   { return @BASE_DIR                }
    }
}



# _include_compute_path ($path);
# ------------------------------
# Computes the new absolute path from the current
# path and $path
sub _include_compute_path
{
    my $self  = shift;
    my $file  = shift;
    return $file unless ($file =~ /^\./);
    
    my $path = $self->{file};
    ($path)  = $path =~ /(.*)\/.*/;
    $path  ||= '.';
    $path .= '/';
    $path .= $file;
    
    my @path = split /\//, $path;
    my @new_path = ();
    while (scalar @path)
    {
	my $next = shift (@path);
	next if $next eq '.';
	
	if ($next eq '..')
	{
	    die "Cannot go above base directory: $file" if (scalar @new_path == 0);
	    pop (@new_path);
	    next;
	}
	
	push @new_path, $next;
    }
    
    return join '/', @new_path;
}


# Processes the current template object with the information contained in
# %hash. This information can be scalars, hash references, array
# references or objects.
#
# Example:
#
#   my $data_out = $template->process (
#     user   => $user,
#     page   => $page,
#     basket => $shopping_basket,    
#   );
#
# print "Content-Type: text/html\n\n";
# print $data_out;
sub process
{
    my $self = shift;
    
    # ok, from there on we need to override any global
    # variable with stuff that might have been specified
    # when constructing the object
    local $TAINT              = defined $self->{taint}              ? $self->{taint}              : $TAINT;
    local $ERROR_ON_UNDEF_VAR = defined $self->{error_on_undef_var} ? $self->{error_on_undef_var} : $ERROR_ON_UNDEF_VAR;
    local $DISK_CACHE         = defined $self->{disk_cache}         ? $self->{disk_cache}         : $DISK_CACHE;
    local $MEMORY_CACHE       = defined $self->{memory_cache}       ? $self->{memory_cache}       : $MEMORY_CACHE;
    local $MAX_INCLUDES       = defined $self->{max_includes}       ? $self->{max_includes}       : $MAX_INCLUDES;
    local $INPUT              = defined $self->{input}              ? $self->{input}              : $INPUT;
    local $OUTPUT             = defined $self->{output}             ? $self->{output}             : $OUTPUT;
    local $BASE_DIR           = defined $self->{base_dir} ? do { ref $self->{base_dir} ? undef : $self->{base_dir} } : $BASE_DIR;
    local @BASE_DIR           = defined $self->{base_dir} ? do { ref $self->{base_dir} ? @{$self->{base_dir}} : undef } : @BASE_DIR;
    local $LANGUAGE           = defined $self->{default_language}   ? $self->{default_language}   : $LANGUAGE;
    local $DEBUG_DUMP         = defined $self->{debug_dump}         ? $self->{debug_dump}         : $DEBUG_DUMP;
    local $DECODE_CHARSET     = defined $self->{decode_charset}     ? $self->{decode_charset}     : $DECODE_CHARSET;
    local $ENCODE_CHARSET     = defined $self->{encode_charset}     ? $self->{encode_charset}     : $ENCODE_CHARSET;
    
    # prevent infinite includes from happening...
    my $current_includes = $CURRENT_INCLUDES;
    return "ERROR: MAX_INCLUDES : $CURRENT_INCLUDES" if ($CURRENT_INCLUDES > $MAX_INCLUDES);
    local $CURRENT_INCLUDES = $current_includes + 1;
    
    my $res = undef;
    eval {
	my $hash = undef;
	if (ref $_[0] eq 'Petal::Hash') { $hash = shift }
	elsif (ref $_[0] eq 'HASH')     { $hash = new Petal::Hash (%{shift()}) }
	else                            { $hash = new Petal::Hash (@_)         }
	
	my $coderef = $self->_code_memory_cached;
	$res = $coderef->($hash);
	
	$Petal::ENCODE_CHARSET and do {
	    require "Encode.pm";
	    $res = Encode::encode ($Petal::ENCODE_CHARSET, $res);
	};
    };
    
    $self->_handle_error ($@) if (defined $@ and $@);
    return $res;
}


sub _handle_error
{
    my $self = shift;
    my $error = shift;
    
    $Petal::DEBUG_DUMP and do {
	my $tmpdir  = File::Spec->tmpdir();
	my $tmpfile = $$ . '.' . time() . '.' . ( join '', map { chr (ord ('a') + int (rand (26))) } 1..10 );
	my $debug   = "$tmpdir/petal_debug.$tmpfile";
	
	open ERROR, ">$debug" || die "Cannot write-open \">$debug\"";
	
	print ERROR "Error: $error\n";
	ref $error and do {
	    print ERROR "=============\n";
	};
	print "\n";
	
	print ERROR "Petal object dump:\n";
	print ERROR "==================\n";
	print ERROR Dumper ($self);
	print ERROR "\n\n";
	
	print ERROR "Stack trace:\n";
	print ERROR "============\n";
	print ERROR Carp::longmess();
	print ERROR "\n\n";
	
	print ERROR "Template perl code dump:\n";
	print ERROR "========================\n";
	my $dump = eval { $self->_code_with_line_numbers() };
	($dump) ? print ERROR $dump : print ERROR "(no dump available)";
	
	die "[PETAL ERROR] $error. Debug info written in $debug.";
    };
    
    ! $Petal::DEBUG_DUMP and do {
	die "[PETAL ERROR] $error. No debug info written.";
    };
}


# $self->code_with_line_numbers;
# ------------------------------
#   utility method to return the Perl code, each line being prefixed with
#   its number... handy for debugging templates. The nifty line number padding
#   patch was provided by Lucas Saud <lucas.marinho@uol.com.br>.
sub _code_with_line_numbers
{
    my $self = shift;
    my $code = $self->_code_disk_cached;

    # get lines of code
    my @lines = split(/\n/, $code);

    # add line numbers
    my $count = 0;
    @lines = map {
      my $cur_line = $_;
      $count++;

      # space padding so the line numbers nicely line up with each other
      my $line_num = sprintf("%" . length(scalar(@lines)) . "d", $count);

      # put line number and line back together
      "${line_num}. ${cur_line}";
    } @lines;

    return join("\n", @lines);
}


# $self->_file;
# -------------
#   setter / getter for the 'file' attribute
sub _file
{
    my $self = shift;
    $self->{file} = shift if (@_);
    $self->{file} =~ s/^\///;
    return $self->{file};
}


# $self->_file_path;
# ------------------
#   computes the file of the absolute path where the template
#   file should be fetched
sub _file_path
{
    my $self = shift;
    my $file = $self->_file;
    my @dirs = $self->base_dir;
    
    foreach my $dir (@dirs)
    {
	my $base_dir = File::Spec->canonpath ($dir);
	$base_dir = File::Spec->rel2abs ($base_dir) unless ($base_dir =~ /^\//);
	$base_dir =~ s/\/$//;
	my $file_path = File::Spec->canonpath ($base_dir . '/' . $file);
	return $file_path if (-e $file_path and -r $file_path);
    }
    
    Carp::confess ("Cannot find $file in @dirs. (typo? permission problem?)");
}


# $self->_file_data_ref;
# ----------------------
#   slurps the template data into a variable and returns a
#   reference to that variable
sub _file_data_ref
{
    my $self      = shift;
    my $file_path = $self->_file_path;
    
    use bytes;
    open FP, "<$file_path" || die 'Cannot read-open $file_path';
    my $res = join '', <FP>;
    close FP;
    no bytes;
    
    $Petal::DECODE_CHARSET and do {
	require "Encode.pm";
	$res = Encode::decode ($Petal::DECODE_CHARSET, $res);
    };
    
    # kill template comments
    $res =~ s/\<!--\?.*?\-->//gsm;
    return \$res;
}


# $self->_code_disk_cached;
# -------------------------
#   Returns the Perl code data, using the disk cache if
#   possible
sub _code_disk_cached
{
    my $self = shift;
    my $file = $self->_file_path;
    my $code = (defined $DISK_CACHE and $DISK_CACHE) ? Petal::Cache::Disk->get ($file) : undef;
    unless (defined $code)
    {
	my $data_ref = $self->_file_data_ref;
	$data_ref    = $self->_canonicalize;

	load_code_generator();
	$code = $CodeGenerator->process ($data_ref, $self);
	Petal::Cache::Disk->set ($file, $code) if (defined $DISK_CACHE and $DISK_CACHE);
    }
    return $code;
}


# $self->_code_memory_cached;
# ---------------------------
#   Returns the Perl code data, using the disk cache if
#   possible
sub _code_memory_cached
{
    my $self = shift;
    my $file = $self->_file_path;
    my $code = (defined $MEMORY_CACHE and $MEMORY_CACHE) ? Petal::Cache::Memory->get ($file) : undef;
    unless (defined $code)
    {
	my $code_perl = $self->_code_disk_cached;
        my $VAR1 = undef;
	
	if (0) # if ($TAINT) - doesn't work with repeat object
	{
	    # important line, don't remove
	    ($code_perl) = $code_perl =~ m/^(.+)$/s;
	    my $cpt = Safe->new ("Petal::CPT");
	    $cpt->permit ('entereval');
	    $cpt->permit ('leaveeval');
	    $cpt->permit ('require');
	    $cpt->share_from ( 'Petal::Hash_Repeat', [ qw /$CUR $MAX/ ] );
	    
	    $cpt->reval($code_perl);
	    confess ($@ . "\n" . $self->_code_with_line_numbers) if $@;
	    
	    # remove silly warning '"Petal::CPT::VAR1" used only once'
	    $Petal::CPT::VAR1 if (0);
	    $code = $Petal::CPT::VAR1;
	}
	else
	{
	    eval "$code_perl";
	    confess ($@ . "\n" . $self->_code_with_line_numbers) if $@;
	    $code = $VAR1;
	}
	
        Petal::Cache::Memory->set ($file, $code) if (defined $MEMORY_CACHE and $MEMORY_CACHE);
    }
    return $code;
}


# $self->_code_cache;
# -------------------
#   Returns TRUE if this object uses the code cache, FALSE otherwise
sub _memory_cache
{
    my $self = shift;
    return $self->{memory_cache} if (defined $self->{memory_cache});
    return $MEMORY_CACHE;
}


# $self->_canonicalize;
# ---------------------
#   Returns the canonical data which will be sent to the
#   Petal::CodeGenerator module
sub _canonicalize
{
    my $self = shift;
    my $parser_type        = $INPUTS->{$INPUT}   || confess "unknown \$Petal::INPUT = $INPUT";
    my $canonicalizer_type = $OUTPUTS->{$OUTPUT} || confess "unknown \$Petal::OUTPUT = $OUTPUT";
    
    my $data_ref = $self->_file_data_ref;
    my $parser = $parser_type->new;
    return $canonicalizer_type->process ($parser, $data_ref);
}


1;

=head1 NAME

Petal - Perl Template Attribute Language - TAL for Perl!


=head1 SYNOPSIS

in your Perl code:

  use Petal;
  my $template = new Petal ('foo.xhtml');
  print $template->process (bar => 'BAZ');


in foo.xhtml

  <html xmlns:tal="http://purl.org/petal/1.0/">
    <body tal:content="bar">Dummy Content</body>
  </html>


and you get something like:

  <html>
    <body>BAZ</body>
  </html>


=head1 SUMMARY

Petal is a XML based templating engine that is able to process any
kind of XML, XHTML and HTML.

Petal borrows a lot of good ideas from the Zope Page Templates TAL
specification, it is very well suited for the creation of WYSIWYG XHTML
editable templates.

The idea is to further enforce the separation of logic from presentation. With
Petal, graphic designers can use their favorite WYSIWYG editor to easily edit
templates without having to worry about the loops and ifs which happen behind
the scene.


=head1 NAMESPACE

Although this is not mandatory, Petal templates should include use the namespace
L<http://purl.org/petal/1.0/>. Example:

    <html xml:lang="en"
          lang="en"
          xmlns="http://www.w3.org/1999/xhtml"
          xmlns:tal="http://purl.org/petal/1.0/">

      Blah blah blah...
      Content of the file
      More blah blah...
    </html>

If you do not specify the namespace, Petal will by default try to use the
C<petal:> prefix. However, in all the examples of this POD we'll use the
C<tal:> prefix to avoid too much typing.


=head1 KICKSTART

Let's say you have the following Perl code:

    use Petal;
    local $Petal::OUTPUT = 'XHTML';

    my $template = new Petal ('foo.xhtml');
    template->process ( my_var => my_var() );

some_object() is a subroutine that returns some kind of object, may it be a scalar,
object, array referebce or hash reference. Let's see what we can do...


=head2 Version 1: Prototype

    <!--? This is a template comment.
          It will not appear in the output -->
    <html xmlns:tal="http://purl.org/petal/1.0/">
      <body>
        This is the variable 'my_var' : ${my_var}.
      </body>
    </html>


And if C<my_var> contained I<Hello World>, Petal would have outputted:

    <html>
      <body>
        This is the variable 'my_var' : Hello World.
      </body>
    </html>


Now let's say that C<my_var> is a hash reference as follows:

    $VAR1 = { hello_world => 'Hello, World' }


To output the same result, you would write:

    This is the variable 'my_var' : ${my_var/hello_world}.


=head2 Version 2: WYSIWYG friendly.

The problem with the above page is that when you edit it with a WYSIWYG editor,
or simply open it in your browser, you will see:

    This is the variable 'my_var' : ${my_var/hello_world}.

Ideally you don't want your graphic designers to worry about
variable names... and that's where TAL kicks in. Using TAL
you can do:

    This is the variable 'my_var' :
    <span tal:replace="my_var/hello_world">Hola, Mundo!</span>

Now you can open your template in any WYSIWYG tool (mozilla composer,
frontpage, dreamweaver, adobe golive...) and work with less risk of damaging
your petal commands.


=head2 Version 3: Object-oriented version

Let's now say that C<my_var> is actually an object with a method hello_world()
that returns I<Hello World>. To output the same result, your line:

    <span tal:replace="my_var/hello_world">Hola, Mundo!</span>

Would become:

    <span tal:replace="my_var/hello_world">Hola, Mundo!</span>

Look carefully at those two lines. That's right. There are identical. Petal
lets you access hashes and objects in an entirely transparent way.

This high level of polymorphism means that in most cases you can maintain your
code, swap hashes for objects, and not change a single line of your template
code.


=head2 Version 4: Personalizable

Now let's say that your method some_object() can take an optional
argument so that C<$my_var->hello_world ('Jack')> returns I<Hello Jack>.

You would write:

    <span tal:replace="my_var/hello_world 'Jack'">Hola, Mundo!</span>


Optionally, you can get rid of the quotes by using two dashes, a la GNU
command-line option:

    <span tal:replace="my_var/hello_world --Jack">Hola, Mundo!</span>


So you can pass parameters to methods using double dashes or quotes.
Now let us say that your C<my_var> object also has a method current_user()
that returns the current user real name. You can do:

    <span tal:replace="my_var/hello_world my_var/current_user">Hola, Mundo!</span>


TRAP:

You cannot write nested expressions such as:

    ${my_var/hello_world ${my_var/current_user}}

This will NOT work. At least, not yet.


=head2 Version 5: Internationalized

Let's say that you have a directory called C<hello_world> with the following
files:

    hello_world/en.xhtml
    hello_world/fr.xhtml
    hello_world/es.xhtml

You can use Petal as follows in your Perl code:

    use Petal;
    local $Petal::OUTPUT = 'XHTML';

    my $template = new Petal ( file => 'hello_world', lang => 'fr-CA' );
    print $template->process ( my_var => my_var() );

What will happen is that the C<$template> object will try to find a file named
C<fr-CA>, then C<fr>, then will default to <en>. It should work fine for
includes, too!


TIP:

If you feel that 'en' should not be the default language, you can specify a
different default:

    my $template = new Petal (
        file             => 'hello_world',
        language         => 'zh',
        default_language => 'fr' # vive la France!
    );


TRAP:

If you do specify the C<lang> option, you MUST use a path to a template
directory, not a file directory.

Conversely, if you do not specify a C<lang> option, you MUST use a path to a
template file, not a directory.


=head1 OPTIONS

When you create a Petal template object you can specify various options using
name => value pairs as arguments to the constructor.  For example:

  my $template = Petal->new(
    file     => 'gerbils.html',
    base_dir => '/var/www/petshop',
    input    => 'HTML',
    output   => 'HTML',
  );

The recognized options are:


=head2 file => I<filename>

The template filename.  This option is mandatory and has no default.

Note: If you also use 'language' this option should point to a directory.


=head2 base_dir => I<pathname> | [ I<pathname list> ] (default: '.')

The directories listed in this option will be searched in turn to locate the
template file.  A single directory can be specified as a scalar.  For a
directory list use an arrayref.


=head2 input => 'HTML' | 'XHTML' | 'XML' (default: 'XML')

Defines the format of the template files.  Recognised values are:

  'HTML'  - Petal will use HTML::TreeBuilder to parse the template
  'XHTML' - Alias for 'HTML'
  'XML'   - Petal will use XML::Parser to parse the template


=head2 output => 'HTML' | 'XHTML' | 'XML' (default: 'XML')

Defines the format of the data generated as a result of processing the template
files.  Recognised values are:

  'HTML'  - Petal will output XHTML, self-closing certain tags
  'XHTML' - Alias for 'HTML'
  'XML'   - Petal will output generic XML 


=head2 language => I<language code>

For internationalized applications, you can use the 'file' option to point to a
I<directory> and select a language-specific template within that directory
using the 'language' option.  Languages are selected using a two letter code
(eg: 'fr') optionally followed by a hyphen and a two letter country code (eg:
'fr-CA').


=head2 default_language => I<language code> (default: 'en')

This language code will be used if no template matches the selected
language-country or language.


=head2 taint => I<true> | I<false> (default: I<false>)

If set to C<true>, makes perl taint mode happy.


=head2 error_on_undef_var => I<true> | I<false> (default: I<true>)

If set to C<true>, Petal will confess() errors when trying to access undefined
template variables, otherwise an empty string will be returned.


=head2 disk_cache => I<true> | I<false> (default: I<true>)

If set to C<false>, Petal will not use the C<Petal::Cache::Disk> module.


=head2 memory_cache => I<true> | I<false> (default: I<true>)

If set to C<false>, Petal will not use the C<Petal::Cache::Memory> module.


=head2 max_includes => I<number> (default: 30)

The maximum number of recursive includes before Petal stops processing.  This
is to guard against accidental infinite recursions.


=head2 debug_dump => I<true> | I<false> (default: I<true>)

If this option is true, when Petal cannot process a template it will
output lots of debugging information in a temporary file which you can
inspect.


=head2 encode_charset => I<charset> (default: undef)

This option will work only if you use Perl 5.8.

If specified, Petal will assume encode the output in the character set
I<charset>.  Please note that the utf-8 flag will be ALWAYS turned off, even if
you specify I<utf8>.

I<charset> can be any character set that can be used with the module L<Encode>. 


=head2 decode_charser => I<charset> (default: undef)

This option will work only if you use Perl 5.8.

If specified, Petal will assume that the template to be processed (and its
sub-templates) are in the character set I<charset>. 

I<charset> can be any character set that can be used with the module L<Encode>. 


=head2 Global Variables

If you want to use an option throughout your entire program and don't want to
have to pass it to the constructor each time, you can set them globally. They
will then act as defaults unless you override them in the constructor.

  $Petal::BASE_DIR           (use base_dir option)
  $Petal::INPUT              (use input option)
  $Petal::OUTPUT             (use output option)
  $Petal::TAINT              (use taint option)
  $Petal::ERROR_ON_UNDEF_VAR (use error_on_undef_var option)
  $Petal::DISK_CACHE         (use disk_cache option)
  $Petal::MEMORY_CACHE       (use memory_cache option)
  $Petal::MAX_INCLUDES       (use max_includes option)
  $Petal::LANGUAGE           (use default_language option)
  $Petal::DEBUG_DUMP         (use debug_dump option)
  $Petal::ENCODE_CHARSET     (use encode_charset option)
  $Petal::DECODE_CHARSET     (use decode_charset option)


=head1 TAL SYNTAX

This functionality is directly and shamelessly stolen from the excellent TAL
specification: L<http://www.zope.org/Wikis/DevSite/Projects/ZPT/TAL>.


=head2 define

Abstract

  <tag tal:define="variable_name EXPRESSION">

Evaluates C<EXPRESSION> and assigns the returned value to C<variable_name>.

Example

  <!--? sets document/title to 'title' -->
  <span tal:define="title document/title">

Why?

This can be useful if you have a C<very/very/long/expression>.  You can set it
to let's say C<vvle> and then use C<vvle> instead of using
C<very/very/long/expression>.


=head2 condition (ifs)

Abstract

  <tag tal:condition="true:EXPRESSION">
     blah blah blah
  </tag>

Example

  <span tal:condition="true:user/is_authenticated">
    Yo, authenticated!
  </span>

Why?

Conditions can be used to display something if an expression
is true. They can also be used to check that a list exists
before attempting to loop through it.


=head2 repeat (loops)

Abstract

  <tag tal:repeat="element_name EXPRESSION">
     blah blah blah
  </tag>

Example:

  <li tal:repeat="user system/user_list">$user/real_name</li>

Why?

Repeat statements are used to loop through a list of values,
typically to display the resulting records of a database query.


=head2 attributes

Abstract

  <tag tal:attributes="attr1 EXPRESSION_1; attr2 EXPRESSION_2"; ...">
     blah blah blah
  </tag>

Example

  <a href="http://www.gianthard.com"
     lang="en-gb"
     tal:attributes="href document/href_relative; lang document/lang">

Why?

Attributes statements can be used to template a tag's attributes.


=head2 content

Abstract

  <tag tal:content="EXPRESSION">Dummy Data To Replace With EXPRESSION</tag>

By default, the characters greater than, lesser than, double quote and
ampersand are encoded to the entities I<&lt;>, I<&gt;>, I<&quot;> and I<&amp;>
respectively.  If you don't want them to (because the result of your expression
is already encoded) you have to use the C<structure> keyword.

Example

  <span tal:content="title">Dummy Title</span>

  <span tal:content="structure some/variable">
     blah blah blah
  </span>

Why?

It lets you replace the contents of a tag with whatever value the evaluation of
EXPRESSION returned. This is handy because you can fill your templates with
dummy content which will make them usable in a WYSIWYG tool.


=head2 replace

Abstract

  <tag tal:replace="EXPRESSION">
    This time the entire tag is replaced
    rather than just the content!
  </tag>

Example

  <span tal:replace="title">Dummy Title</span>

Why?

Similar reasons to C<content>. Note however that C<tal:content> and
C<tal:replace> are *NOT* aliases. The former will replace the contents of the
tag, while the latter will replace the whole tag.

Indeed you cannot use C<tal:content> and C<tal:replace> in the same tag.


=head2 omit-tag

Abstract

  <tag tal:omit-tag="EXPRESSION">Some contents</tag>

Example

  <b tal:omit-tag="not:bold">I may not be bold.</b>

If C<not:bold> is evaluated as I<TRUE>, then the <b> tag will be omited.
If C<not:bold> is evaluated as I<FALSE>, then the <b> tag will stay in place.

Why?

omit-tag statements can be used to leave the contents of a tag in place while
omitting the surrounding start and end tags if the expression which is
evaluated is TRUE.

TIP:

If you want to ALWAYS remove a tag, you can use C<omit-tag="string:1">


=head2 on-error

Abstract

  <tag on-error="EXPRESSION">...</tag>

Example

  <p on-error="string:Cannot access object/method!!">
    $object/method
  </p>

Why?

When Petal encounters an error, it usually dies with some obscure error
message. The C<on-error> statement lets you trap the error and replace it
with a proper error message.


=head2 using multiple statements

You can do things like:

  <p tal:define="children document/children"
     tal:condition="children"
     tal:repeat="child children"
     tal:attributes="lang child/lang; xml:lang child/lang"
     tal:content="child/data"
     tal:on-error="string:Ouch!">Some Dummy Content</p>

Given the fact that XML attributes are not ordered, withing the same tag
statements will be executed in the following order:

    define
    condition
    repeat
        attributes
        content
    OR
        replace
    OR
        omit-tag
        content


=head2 aliases

On top of all that, for people who are lazy at typing the following
aliases are provided (although I would recommend sticking to the
defaults):

  * tal:define     - tal:def, tal:set
  * tal:condition  - tal:if
  * tal:repeat     - tal:for, tal:loop, tal:foreach
  * tal:attributes - tal:att, tal:attr, tal:atts
  * tal:content    - tal:inner
  * tal:replace    - tal:outer


TRAP:

Don't forget that the default prefix is C<petal:> NOT C<tal:>, until
you set the petal namespace in your HTML or XML document as follows:

    <html xmlns:tal="http://purl.org/petal/1.0/">


=head1 INCLUDES

Let's say that your base directory is C</templates>,
and you're editing C</templates/hello/index.html>.

From there you want to include C</templates/includes/header.html>


=head2 general syntax

You can use a subset of the XInclude syntax as follows:

  <body xmlns:xi="http://www.w3.org/2001/XInclude">
    <xi:include href="/includes/header.html" />
  </body>


For backwards compatibility reasons, you can omit the first slash, i.e.

  <xi:include href="includes/header.html" />


=head2 relative paths

If you'd rather use a path which is relative to the template itself rather
than the base directory, you can do it but the path MUST start with a dot,
i.e.

  <xi:include href="../includes/header.html" />

  <xi:include href="./subdirectory/foo.xml" />

etc.


=head2 limitations

The C<href> parameter does not support URIs, no other tag than C<xi:include> is
supported, and no other directive than the C<href> parameter is supported at
the moment.

Also note that contrarily to the XInclude specification Petal DOES allow
recursive includes up to C<$Petal::MAX_INCLUDES>. This behavior is very useful
when templating structures which fit well recursive processing such as trees,
nested lists, etc.

You can ONLY use the following Petal directives with Xinclude tags:

  * on-error
  * define
  * condition
  * repeat

C<replace>, C<content>, C<omit-tag> and C<attributes> are NOT supported in
conjunction with XIncludes.


=head1 EXPRESSIONS AND MODIFIERS

Petal has the ability to bind template variables to the following Perl
datatypes: scalars, lists, hash, arrays and objects. The article describes
the syntax which is used to access these from Petal templates.

In the following examples, we'll assume that the template is used as follows:

  my $hashref = some_complex_data_structure();
  my $template = new Petal ('foo.xml');
  print $template->process ( $hashref );

Then we will show how the Petal Expression Syntax maps to the Perl way of
accessing these values.  


=head2 accessing scalar values

Perl expression

  $hashref->{'some_value'};

Petal expression

  some_value

Example

  <!--? Replaces Hello, World with the contents of
        $hashref->{'some_value'}
  -->
  <span tal:replace="some_value">Hello, World</span>


=head2 accessing hashes & arrays

Perl expression

  $hashref->{'some_hash'}->{'a_key'};

Petal expression

  some_hash/a_key

Example

  <!--? Replaces Hello, World with the contents
        of $hashref->{'some_hash'}->{'a_key'}
  -->
  <span tal:replace="some_hash/a_key">Hello, World</span>


Perl expression

  $hashref->{'some_array'}->[12]

Petal expression

  some_array/12

Example

  <!--? Replaces Hello, World with the contents
       of $hashref->{'some_array'}->[12]
  -->
  <span tal:replace="some_array/12">Hello, World</span>

Note: You're more likely to want to loop through arrays:

  <!--? Loops trough the array and displays each values -->
  <ul tal:condition="some_array">
    <li tal:repeat="value some_array"
        tal:content="value">Hello, World</li>
  </ul>


=head2 accessing object methods

Perl expressions

  1. $hashref->{'some_object'}->some_method();
  2. $hashref->{'some_object'}->some_method ('foo', 'bar');
  3. $hashref->{'some_object'}->some_method ($hashref->{'some_variable'})  

Petal expressions

  1. some_object/some_method
  2a. some_object/some_method 'foo' 'bar'
  2b. some_object/some_method "foo" "bar"
  2c. some_object/some_method --foo --bar
  3. some_object/some_method some_variable

Note that the syntax as described in 2c works only if you use strings
which do not contain spaces.

Example

  <p>
    <span tal:replace="value1">2</span> times
    <span tal:replace="value2">2</span> equals
    <span tal:replace="math_object/multiply value1 value2">4</span>
  </p>
    

=head2 composing

Petal lets you traverse any data structure, i.e.

Perl expression

  $hashref->{'some_object'}
          ->some_method()
          ->{'key2'}
          ->some_other_method ( 'foo', $hash->{bar} );

Petal expression

  some_object/some_method/key2/some_other_method --foo bar


=head2 true:EXPRESSION

  If EXPRESSION returns an array reference
    If this array reference has at least one element
      Returns TRUE
    Else
      Returns FALSE

  Else
    If EXPRESSION returns a TRUE value (according to Perl 'trueness')
      Returns TRUE
    Else
      Returns FALSE

the C<true:> modifiers should always be used when doing Petal conditions.


=head2 false:EXPRESSION

I'm pretty sure you can work this one out by yourself :-)


=head2 set:variable_name EXPRESSION

Sets the value returned by the evaluation of EXPRESSION in
C<$hash->{variable_name}>. For instance:

Perl expression:

  $hash->{variable_name} = $hash->{object}->method();

Petal expression:

  set:variable_name object/method


=head2 string:STRING_EXPRESSION

The C<string:> modifier lets you interpolate petal expressions within a string
and returns the value.

  string:Welcome $user/real_name, it is $date!

Alternatively, you could write:

  string:Welcome ${user/real_name}, it is ${date}!
  
The advantage of using curly brackets is that it lets you interpolate
expressions which invoke methods with parameters, i.e.

  string:The current CGI 'action' param is: ${cgi/param --action}


=head1 UGLY SYNTAX

For certain things which are not doable using TAL you can use what
I call the UGLY SYNTAX. The UGLY SYNTAX is UGLY, but it can be handy
in some cases.

For example consider that you have a list of strings:

    $my_var = [ 'Foo', 'Bar', 'Baz' ];
    $template->process (my_var => $my_var, buz => $buz);


And you want to display:

  <title>Hello : Foo : Bar : Baz</title>

Which is not doable with TAL without making the XHTML invalid.
With the UGLY SYNTAX you can do:

    <title>Hello<?for name="string my_var"?> : <?var name="string"?><?end?></title>

Of course you can freely mix the UGLY SYNTAX with other Petal
syntaxes. So:

    <title><?for name="string my_var"?> $string <?end?></title>

Mind you, if you've managed to read the doc this far I must confess
that writing:

    <h1>$string</h1>

instead of:

    <h1 tal:replace="string">Dummy</h1>

is UGLY too. I would recommend to stick with TAL wherever you can.
But let's not disgress too much.


=head2 variables

Abstract

  <?var name="EXPRESSION"?>

Example

  <title><?var name="document/title"?></title>

Why?

Because if you don't have things which are replaced by real values in your
template, it's probably a static page, not a template... :) 


=head2 if / else constructs

Usual stuff:

  <?if name="user/is_birthay"?>
    Happy Birthday, $user/real_name!
  <?else?>
    What?! It's not your birthday?
    A very merry unbirthday to you! 
  <?end?>

You can use C<condition> instead of C<if>, and indeed you can use modifiers:

  <?condition name="false:user/is_birthay"?>
    What?! It's not your birthday?
    A very merry unbirthday to you! 
  <?else?>
    Happy Birthday, $user/real_name!
  <?end?>

Not much else to say!


=head2 loops

Use either C<for>, C<foreach>, C<loop> or C<repeat>. They're all the same
thing, which one you use is a matter of taste. Again no surprise:

  <h1>Listing of user logins</h1>
  <ul>
    <?repeat name="user system/list_users"?>
      <li><?var name="user/login"?> :
          <?var name="user/real_name"?></li>
    <?end?>
  </ul>
  

Variables are scoped inside loops so you don't risk to erase an existing
C<user> variable which would be outside the loop. The template engine also
provides the following variables for you inside the loop:

  <?repeat name="foo bar"?>
    <?var name="repeat/index"?>  - iteration number, starting at 0
    <?var name="repeat/number"?> - iteration number, starting at 1
    <?var name="repeat/start"?>  - is it the first iteration?
    <?var name="repeat/end"?>    - is it the last iteration?
    <?var name="repeat/inner"?>  - is it not the first and not the last iteration?
    <?var name="repeat/even"?>   - is the count even?
    <?var name="repeat/odd"?>    - is the count odd?
  <?end?>

Again these variables are scoped, you can safely nest loops, ifs etc...  as
much as you like and everything should be fine.


=head2 includes

The XInclude syntax should be preferred over this...

  <?include file="include.xml"?>

It will include the file 'include.xml', using the current C<@Petal::BASE_DIR>
directory list.

If you want use XML::Parser to include files, you should make sure that
the included files are valid XML themselves... FYI XML::Parser chokes on
this:

    <p>foo</p>
    <p>bar</p>

But this works:

    <div>
      <p>foo</p>
      <p>bar</p>
    </div>

(Having only one top element is part of the XML spec).


=head1 ADVANCED PETAL


=head2 writing your own modifiers

Petal lets you write your own modifiers, either using coderefs
or modules.


=head3 Coderefs

Let's say that you want to write an uppercase: modifier, which
would uppercase the result of an expression evaluation, as in:

  uppercase:string:Hello, World

Would return

  HELLO, WORLD

Here is what you can do:

  # don't forget the trailing colon in C<uppercase:> !!
  $Petal::Hash::MODIFIERS->{'uppercase:'} = sub {
      my $hash = shift;
      my $args = shift;

      my $result = $hash->fetch ($args);
      return uc ($result);
  };


=head3 Modules.

You might want to use a module rather than a coderef. Here is the example above
reimplemented as a module:

    package Petal::Hash::UpperCase;
    use strict;
    use warnings;
  
    sub process {
      my $class = shift;
      my $hash  = shift;
      my $args  = shift;

      my $result = $hash->fetch ($args);
      return uc ($result);
    }

    1;

As long as your module is in the namespace Petal::Hash::<YourModifierName>,
Petal will automatically pick it up and assign it to its lowercased
name, i.e. in our example C<uppercase:>.

If your modifier is OUTSIDE Petal::Hash::<YourModifierName>, you need to
make Petal aware of its existence as follows:

  use MyPetalModifier::UpperCase;
  $Petal::Hash::MODIFIERS->{'uppercase:'} = 'MyPetalModifier::UpperCase';


=head1 Expression keywords


=head3 XML encoding / structure keyword

By default Petal will encode C<&>, C<<>, C<>> and C<"> to C<&amp;>, C<&lt;>,
C<&gt> and C<&quot;> respectively. However sometimes you might want to display
an expression which is already encoded, in which case you can use the
C<structure> keyword.

  structure my/encoded/variable

Note that this is a language I<keyword>, not a modifier. It does not use a
trailing colon.


=head3 Petal::Hash caching and fresh keyword 

Petal caches the expressions which it resolves, i.e. if you write the
expression:

  string:$foo/bar, ${baz/buz/blah}

Petal::Hash will compute it once, and then for subsequent accesses to that
expression always return the same value. This is almost never a problem, even
for loops because a new Petal::Hash object is used for each iteration in order
to support proper scoping.

However, in some rare cases you might not want to have that behavior, in which
case you need to prefix your expression with the C<fresh> keyword, i.e. 

  fresh string:$foo/bar, ${baz/buz/blah}

You can use C<fresh> with C<structure> if you need to:

  fresh structure string:$foo/bar, ${baz/buz/blah}

However the reverse does not work:

  <!--? VERY BAD, WON'T WORK !!! -->
  structure fresh string:$foo/bar, ${baz/buz/blah}


=head2 TOY FUNCTIONS (For debugging or if you're curious)


=head3 perl -MPetal -e canonical template.xml

Displays the canonical template for template.xml.
You can set C<$Petal::INPUT> using by setting the PETAL_INPUT environment variable.
You can set C<$Petal::OUTPUT> using by setting the PETAL_OUTPUT environment variable.


=head3 perl -MPetal -e code template.xml

Displays the perl code for template.xml.
You can set C<$Petal::INPUT> using by setting the PETAL_INPUT environment variable.
You can set C<$Petal::OUTPUT> using by setting the PETAL_OUTPUT environment variable.


=head3 perl -MPetal -e lcode template.xml

Displays the perl code for template.xml, with line numbers.
You can set C<$Petal::INPUT> using by setting the PETAL_INPUT environment variable.
You can set C<$Petal::OUTPUT> using by setting the PETAL_OUTPUT environment variable.


=head2 What does Petal do internally?

The cycle of a Petal template is the following:

    1. Read the source XML template
    2. $INPUT (XML or HTML) throws XML events from the source file
    3. $OUTPUT (XML or HTML) uses these XML events to canonicalize the template
    4. Petal::CodeGenerator turns the canonical template into Perl code
    5. Petal::Cache::Disk caches the Perl code on disk
    6. Petal turns the perl code into a subroutine
    7. Petal::Cache::Memory caches the subroutine in memory
    8. Petal executes the subroutine

If you are under a persistent environement a la mod_perl, subsequent calls to
the same template will be reduced to step 8 until the source template changes.

Otherwise, subsequent calls will resume at step 6, until the source template
changes.


=head1 DECRYPTING WARNINGS AND ERRORS


=head2 "Cannot import module $module. Reason: $@" (nonfatal)

Petal was not able to import one of the modules. This error warning will be
issued when Petal is unable to load a plugin because it has been badly install
or is just broken.


=head2 "Petal modifier encode: is deprecated" (nonfatal)

You don't need to use encode:EXPRESSION to XML-encode expression anymore,
Petal does it for you. encode: has been turned into a no-op.


=head2 Cannot find value for ... (FATAL)

You tried to invoke an/expression/like/this/one but Petal could not resolve
it. This could be because an/expression/like evaluated to undef and hence the
remaining this/one could not be resolved.

Usually Petal gives you a line number and a dump of your template as Perl
code. You can look at the perl code to try to determine the faulty bit in
your template.


=head2 not well-formed (invalid token) at ... (FATAL)

Petal was trying to parse a file that is not well-formed XML or that has strange
entities in it. Try to run xmllint on your file to see if it's well formed or
try to use the $Petal::INPUT = 'XHTML' option.


=head2 other errors

Either I've forgot to document it, or it's a bug. Send an email to the Petal
mailing list or at L<mailto://jhiver@mkdoc.com>.


=head1 EXPORTS

None.


=head1 KNOWN BUGS

The XML::Parser wrapper only cannot expand entities C<&lt;>, C<&gt;>, C<&amp;>
and C<&quot;>. Besides, I can't get it to NOT expand entities in 'Stream' mode.

HTML::TreeBuilder expands all entities, hence &nbsp;s are lost / converted to
whitespaces.

XML::Parser is deprecated and should be replaced by SAX handlers at some point.


=head1 AUTHOR

Copyright 2003 - MKDoc Holdings Ltd.

Authors: Jean-Michel Hiver <jhiver@mkdoc.com>, 
         Fergal Daly <fergal@esatclear.ie>,
	 and others.

This module free software and is distributed under the same license as Perl
itself. Use it at your own risk.

Thanks to everybody on the list who contributed to Petal in the form of
patches, bug reports and suggestions. See README for a list of contributors.


=head1 SEE ALSO

Join the Petal mailing list:

  http://lists.webarch.co.uk/mailman/listinfo/petal

Mailing list archives:

  http://lists.webarch.co.uk/pipermail/petal


Have a peek at the TAL / TALES / METAL specs:

  http://www.zope.org/Wikis/DevSite/Projects/ZPT/TAL
  http://www.zope.org/Wikis/DevSite/Projects/ZPT/TALES
  http://www.zope.org/Wikis/DevSite/Projects/ZPT/METAL


Any extra questions? jhiver@mkdoc.com.
