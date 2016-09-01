package DCITools;

use 5.006;
use strict;
use warnings;

use Moose;
use WWW::Mechanize;
use WWW::Scripter;

has '_ua'  => (is => 'ro', isa => 'WWW::Mechanize',
             default => sub {WWW::Mechanize->new});
has '_xua' => (is => 'ro', isa => 'WWW::Scripter',
             default => sub {my $ua = WWW::Scripter->new;
                             $ua->agent_alias('Windows IE 6');
                             $ua->use_plugin('JavaScript');
                             $ua;
                            });

my $primes = [43, 47, 53, 71, 73, 31, 37, 41, 59, 61, 67, 29];

=head1 NAME

DCITools - Tools for working with DCI numbers and databases

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use DCITools;

    my $lookup = 8102291717;
    my $tools = new DCITools;

    $tools->dcix_login('DCI Number', 'Password') || die "Can't log in to Judge Center";
    $tools->apps_login('Username', 'Password') || die "Can't log in to JudgeApps";

    my $valid = $tools->checkvalid($lookup);
    print "DCI Number $dci valid? ".$valid."\n";
    my $res = $tools->get_other_versions($lookup);
    foreach my $k (sort {$a <=> $b} keys %$res) {
        my $v = $res->{$k};
        my $judge = $tools->dcix_force_import($v);
        my $level = $judge ? $judge->{'level'} : 0;
        my $name = $judge ? $judge->{'first'} .' '. $judge->{'last'} : '';
        my $location = $judge ? $judge->{'city'} .', '. $judge->{'region'} .', '. $judge->{'country'} : '';
        printf('L%1d %10d: %s, %s'."\n", $level, $v, $name, $location);
    }

=head1 CAVEATS

This should be treated at completely EXPERIMENTAL, for several reasons. First,
this is pre-alpha code. The API is incomplete, error handling is non-existent,
and there is no differentiation between methods that require a privileged
account, a normal account, or no account at all. Second, it relies on
WWW::Scripter, which is itself an alpha release at time of writing. Finally,
it relies on screen-scraping interfaces which are not part of any stable API.
Use at your own risk.

DCI, DCIX, and other marks and names used in this module may be (c) or TM
Wizards of the Coast, LLC; Hasbro, Inc.; or other entities. They are used by
reference only. No affiliation or endorsement is claimed. Your use of this
library may be subject to the Terms of Use or Acceptable Use Policy of the
sites you access. Browse responsibly.

=head1 METHODS

=head2 checkvalid($number)

Interpreting the argument as a DCI Registration Number, reports whether the
Registration Number has a valid internal checksum. Registration Numbers with
a number of digits other than 6, 8, or 10 cannot be checked because there is
no checksum present. Returns 1 if there is a checksum and it is valid, 0
otherwise.

=cut

sub checkvalid {
    my $self = shift;
    my $number = shift;
    
    my @digits = split('', "$number");
    
    return 0 unless map {$_ == scalar(@digits)} (6, 8, 10);
    
    my $cd = $self->calc_cd(@digits[1..$#digits]);
    
    return $cd == $digits[0] ? 1 : 0;
}

=head2 calc_cd($number)

Interpreting the argument as all but the first digit of a DCI Registration
Number, calculates the checkdigit which should be prepended to create a
valid Registration Number. https://github.com/marumari/decklist/issues/4

=cut

sub calc_cd {
    my $self = shift;
    my @number = @_;
    
    my $sum = 0;
    
    foreach my $d (0..$#number) {
        $sum += $number[$d]*$primes->[$d];
    }
    
    my $cd = 1 + (int($sum/10)%9);
    return $cd;
}

=head2 get_other_versions($number)

Interpreting the argument as a DCI Registration Number, returns all equivalent
Registration Numbers. Return value is a key-value array where the keys are the
length of each number, and the values are the numbers themselves.

=cut

sub get_other_versions {
    my $self = shift;
    my $number = shift;
    
    my @digits = split('', "$number");
    my $len = scalar(@digits);
    
    my $ret;
    
    $ret->{$len} = $number;
    
    # Growth
    if ($len == 4) {
        unshift @digits, 0;
        $len++;
    }
    if ($len == 5) {
        unshift @digits, $self->calc_cd(@digits);
        $len++;
        $ret->{$len} = join('', @digits);
    }
    if ($len == 6) {
        unshift @digits, 0;
        unshift @digits, $self->calc_cd(@digits);
        $len += 2;
        $ret->{$len} = join('', @digits);
    }
    if ($len == 8) {
        unshift @digits, 0;
        unshift @digits, $self->calc_cd(@digits);
        $len += 2;
        $ret->{$len} = join('', @digits);
    }
    
    # Shrinking
    while ($self->checkvalid(join('', @digits)) && $digits[1] == 0 && $len >= 6) {
        $len -= 2;
        @digits = @digits[2..$#digits];
        $ret->{$len} = join('', @digits);
    } 
    if ($digits[1] == 0 && $len == 6) {
        $len -= 2;
        @digits = @digits[2..$#digits];
        $ret->{$len} = join('', @digits);
    }
    
    return $ret;
}

=head2 dcix_login($user, $pass)

Attempts to log in to DCIX using the provided username and password.

=cut

sub dcix_login {
    my $self = shift;
    my $user = shift;
    my $pass = shift;
    
    my $res = $self->_xua->get('https://judge.wizards.com/login.aspx');
    $res = $self->_xua->submit_form(
        with_fields =>
            {'ctl00$phMainContent$DCINumberTextBox' => $user,
             'ctl00$phMainContent$PasswordTextBox' => $pass});
    if ($res->decoded_content =~ /welcome to the Judge Center!/) {
        return 1;
    } else {
        print $res->decoded_content;
        return 0;
    }
}

sub check_dcix {
    my $self = shift;
    my $number = shift;

    my $res = $self->_xua->get('https://judge.wizards.com/people.aspx?dcinumber='.$number);
    
    if ($res->decoded_content =~ /Your search returned no results/) {
        # No user
        return 0;
    } elsif ($res->decoded_content =~ /DCI Level:<\/b>\s+(\d)/sm) {
        # Got level
        return $self->dcix_parse_people($res);
    } else {
        # No idea
        return 0;
    }
}

sub dcix_force_import {
    my $self = shift;
    my $number = shift;

    my $res = $self->_xua->get('https://judge.wizards.com/people.aspx');
    $res = $self->_xua->follow_link(text => 'FIND');
    $res = $self->_xua->submit_form(
        with_fields =>
            {'_dpmt$_mt$ctl06$_ucPersonSelector$PersonNameTextBox' => $number},
        button => '_dpmt$_mt$ctl06$btnView');
    if ($res->decoded_content =~ /Your search returned no results/) {
        # No user
        return 0;
    } elsif ($res->decoded_content =~ /DCI Level:<\/b>\s+(\d)/sm) {
        # Got level
        my $ret = $self->dcix_parse_people($res);
        if ($ret->{'level'} == 0 && $ret->{'reviewsin'} > 0 && $ret->{'examsin'} > 0) {
            $res = $self->_xua->click('_dpmt$_mt$ctl10$btnRefresh');
            $ret = $self->dcix_parse_people($res);
        }
        return $ret;
    } else {
        # No idea
        return 0;
    }
}

sub dcix_parse_people {
    my $self = shift;
    my $res = shift;
    
    my $ret;
    
    if ($res->decoded_content =~ /DCI Level:<\/b>\r?\n?\s+(\d)/) {
        $ret->{'level'} = $1;
    }
    if ($res->decoded_content =~ /First Name:<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'first'} = $1;
    }
    if ($res->decoded_content =~ /Last Name:<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'last'} = $1;
    }
    if ($res->decoded_content =~ /City:<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'city'} = $1;
    }
    if ($res->decoded_content =~ /Region:<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'region'} = $1;
    }
    if ($res->decoded_content =~ /Country:<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'country'} = $1;
    }
    if ($res->decoded_content =~ /Expiration:<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'expiration'} = $1;
    }
    if ($res->decoded_content =~ /Reviews \(Reviewer\):<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'reviewsin'} = $1;
    }
    if ($res->decoded_content =~ /Reviews \(Subject\):<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'reviewsout'} = $1;
    }
    if ($res->decoded_content =~ /Exams \(Creator\):<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'examsout'} = $1;
    }
    if ($res->decoded_content =~ /Exams \(Candidate\):<\/b>\r?\n?\s+([^<\s].+?)\r?\n/) {
        $ret->{'examsin'} = $1;
    }
    
    return $ret;
}

sub apps_login {
    my $self = shift;
    my $user = shift;
    my $pass = shift;
    
    my $res = $self->_ua->get('http://apps.magicjudges.org/accounts/login/');
    $res = $self->_ua->submit_form(
        with_fields =>
            {'username' => $user,
             'password' => $pass});
    if ($res->decoded_content =~ /Home/) {
        return 1;
    } else {
        print $res->decoded_content;
        return 0;
    }
}

sub apps_get_pending_accounts {
    my $self = shift;
    
    my $res = $self->_ua->get('http://apps.magicjudges.org/accounts/review/');
    my $text = $res->decoded_content;
    my $ret;
    
    while ($text =~ m|
      \s+ <tr \s class="\w+">       \r?\n
      \s+   <td>([^<]+?)</td>       \r?\n
      \s+   <td>([^<]+?)</td>       \r?\n
      \s+   <td>([^<]+?)</td>       \r?\n
      \s+   <td>([^<]+?)</td>       \r?\n
      \s+   <td><a \s href="https://judge.wizards.com/people.aspx\?dcinumber=(\d+?)" \s target="_blank">\d+?</a></td>       \r?\n
      \s+   <td><a \s href="https://judge.wizards.com/people.aspx\?name=[^"]+?" \s target="_blank">Link</a></td>       \r?\n
      \s+   <td><input \s type="checkbox" \s name="accept_user_id_(\d+?)" \s /></td>       \r?\n
      \s+   <td><input \s type="checkbox" \s name="decline_user_id_\d+?" \s /></td>       \r?\n
      \s+   <td><input \s type="checkbox" \s name="accept_l0_user_id_\d+?" \s /></td>       \r?\n
      \s+ </tr>
      |xg) {
        my ($name, $levelstr, $location, $registered, $dci, $appsid) = ($1, $2, $3, $4, $5, $6);
        my $level = $levelstr =~ /Level (\d)/ ? $1 : 0;
        push @$ret, {'name' => $name,
                     'level' => $level,
                     'location' => $location,
                     'registered' => $registered,
                     'dci' => $dci,
                     'appsid' => $appsid
                    };
    }
    return $ret;
}

=head1 AUTHOR

Dan Collins, C<< <DCOLLINS at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dcitools at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DCITools>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DCITools


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=DCITools>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/DCITools>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/DCITools>

=item * Search CPAN

L<http://search.cpan.org/dist/DCITools/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2016 Dan Collins.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; version 2 dated June, 1991 or at your option
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

A copy of the GNU General Public License is available in the source tree;
if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA


=cut

1; # End of DCITools
