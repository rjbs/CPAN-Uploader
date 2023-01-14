use v5.12.0;
use warnings;

use Test::More tests => 2;
use File::Temp qw/ tempdir /;
use File::Spec ();

use CPAN::Uploader;

{
  my $tempdir = tempdir(CLEANUP => 1);
  my $filename = File::Spec->catfile($tempdir, 'pauserc.txt');
  {
    open my $out, '>', $filename;
    print {$out} <<'EOF';
user BUGSBUNNY
password hunter12

non_interactive
EOF
    close ($out);

    my %conf;
    eval
    {
      %conf = CPAN::Uploader->_parse_dot_pause($filename);
    };
    my $err = $@;
    like ($err, qr#\A\QLine 4 (non_interactive) does not match the "key value" format.\E#,
      "Correct error on line without a value."
    );
  }

  {
    open my $out, '>', $filename;
    print {$out} <<'EOF';
user BUGSBUNNY
user LEFTPADDER
password hunter12
EOF
    close ($out);

    my %conf;
    eval
    {
      %conf = CPAN::Uploader->_parse_dot_pause($filename);
    };
    my $err = $@;
    like ($err, qr#\A\Qmultiple entries for user\E#,
      "Correct spelling",
    );
  }
}

