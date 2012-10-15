use strict;
use warnings;
package CPAN::Uploader;
# ABSTRACT: upload things to the CPAN

=head1 ORIGIN

This code is mostly derived from C<cpan-upload-http> by Brad Fitzpatrick, which
in turn was based on C<cpan-upload> by Neil Bowers.  I (I<rjbs>) didn't want to
have to use a C<system> call to run either of those, so I refactored the code
into this module.

=cut

use Carp ();
use File::Basename ();
use File::Spec;
use HTTP::Request::Common qw(POST);
use HTTP::Status;
use LWP::UserAgent;

my $UPLOAD_URI = $ENV{CPAN_UPLOADER_UPLOAD_URI}
              || 'http://pause.perl.org/pause/authenquery';

=method upload_file

  CPAN::Uploader->upload_file($file, \%arg);

  $uploader->upload_file($file);

Valid arguments are:

  user       - (required) your CPAN / PAUSE id
  password   - (required) your CPAN / PAUSE password
  subdir     - the directory (under your home directory) to upload to
  http_proxy - uri of the http proxy to use
  upload_uri - uri of the upload handler; usually the default (PAUSE) is right
  debug      - if set to true, spew lots more debugging output

This method attempts to actually upload the named file to the CPAN.  It will
raise an exception on error.

=cut

use Data::Dumper;
sub upload_file {
  my ($self, $file, $arg) = @_;

  Carp::confess(q{don't supply %arg when calling upload_file on an object})
    if $arg and ref $self;

  # class call with no args is no good
  Carp::confess(q{need to supply %arg when calling upload_file from the class})
    if not (ref $self) and not $arg;

  $self = $self->new($arg) if $arg;

  if ($arg->{dry_run}) {
    $self->log("By request, cowardly refusing to do anything at all.");
    $self->log(
      "The following arguments would have been used to upload: \n"
      . '$self: ' . Dumper($self)
      . '$file: ' . Dumper($file)
    );
  } else {
    $self->_upload($file);
  }
}

sub _ua_string {
  my ($self) = @_;
  my $class   = ref $self || $self;
  my $version = $class->VERSION;

  return "$class/$version";
}

sub uri { shift->{upload_uri} || $UPLOAD_URI }
sub target { shift->{target} || 'PAUSE' }

sub _upload {
  my $self = shift;
  my $file = shift;

  $self->log("registering upload with " . $self->target . " web server");

  my $agent = LWP::UserAgent->new;
  $agent->agent( $self->_ua_string );

  $agent->env_proxy;
  $agent->proxy(http => $self->{http_proxy}) if $self->{http_proxy};

  my $uri = $self->{upload_uri} || $UPLOAD_URI;

  my $request = POST(
    $uri,
    Content_Type => 'form-data',
    Content      => {
      HIDDENNAME                        => $self->{user},
      CAN_MULTIPART                     => 1,
      pause99_add_uri_upload            => File::Basename::basename($file),
      SUBMIT_pause99_add_uri_httpupload => " Upload this file from my disk ",
      pause99_add_uri_uri               => "",
      pause99_add_uri_httpupload        => [ $file ],
      ($self->{subdir} ? (pause99_add_uri_subdirtext => $self->{subdir}) : ()),
    },
  );

  $request->authorization_basic($self->{user}, $self->{password});

  my $DEBUG_METHOD = $ENV{CPAN_UPLOADER_DISPLAY_HTTP_BODY}
                   ? 'as_string'
                   : 'headers_as_string';

  $self->log_debug(
    "----- REQUEST BEGIN -----\n" .
    $request->$DEBUG_METHOD . "\n" .
    "----- REQUEST END -------\n"
  );

  # Make the request to the PAUSE web server
  $self->log("POSTing upload for $file to $uri");
  my $response = $agent->request($request);

  # So, how'd we do?
  if (not defined $response) {
    die "Request completely failed - we got undef back: $!";
  }

  if ($response->is_error) {
    if ($response->code == RC_NOT_FOUND) {
      die "PAUSE's CGI for handling messages seems to have moved!\n",
        "(HTTP response code of 404 from the ", $self->target, " web server)\n",
        "It used to be: ", $uri, "\n",
        "Please inform the maintainer of $self.\n";
    } else {
      die "request failed with error code ", $response->code,
        "\n  Message: ", $response->message, "\n";
    }
  } else {
    $self->log_debug($_) for (
      "Looks OK!",
      "----- RESPONSE BEGIN -----\n" .
      $response->$DEBUG_METHOD . "\n" .
      "----- RESPONSE END -------\n"
    );

    $self->log($self->target . " add message sent ok [" . $response->code . "]");
  }
}


=method new

  my $uploader = CPAN::Uploader->new(\%arg);

This method returns a new uploader.  You probably don't need to worry about
this method.

Valid arguments are the same as those to C<upload_file>.

=cut

sub new {
  my ($class, $arg) = @_;

  $arg->{$_} or Carp::croak("missing $_ argument") for qw(user password);
  bless $arg => $class;
}

=method read_config_file

  my $config = CPAN::Uploader->read_config_file( $filename );

This reads the config file and returns a hashref of its contents that can be
used as configuration for CPAN::Uploader.

If no filename is given, it looks for F<.pause> in the user's home directory
(from the env var C<HOME>, or the current directory if C<HOME> isn't set).

See L<cpan_upload/CONFIGURATION> for the config format.

=cut

sub read_config_file {
  my ($class, $filename) = @_;

  unless ($filename) {
    my $home  = $ENV{HOME} || '.';
    $filename = File::Spec->catfile($home, '.pause');

    return {} unless -e $filename and -r _;
  }

  # Process .pause
  open my $pauserc, '<', $filename
    or die "can't open $filename for reading: $!";

  my %from_file;
  while (<$pauserc>) {
    chomp;
    next unless $_ and $_ !~ /^\s*#/;

    my ($k, $v) = /^\s*(\w+)\s+(.+)$/;
    Carp::croak "multiple enties for $k" if $from_file{$k};
    $from_file{$k} = $v;
  }

  return \%from_file;
}

=method log

  $uploader->log($message);

This method logs the given string.  The default behavior is to print it to the
screen.  The message should not end in a newline, as one will be added as
needed.

=cut

sub log {
  shift;
  print "$_[0]\n"
}

=method log_debug

This method behaves like C<L</log>>, but only logs the message if the
CPAN::Uploader is in debug mode.

=cut

sub log_debug {
  my $self = shift;
  return unless $self->{debug};
  $self->log($_[0]);
}

1;
