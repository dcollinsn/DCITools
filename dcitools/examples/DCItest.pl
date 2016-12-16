use DCITools;
use Net::SMTP;

my $tools = new DCITools;
$tools->dcix_login('', '')|| die "Can't log in to Judge Center";
$tools->apps_login('', '') || die "Can't log in to JudgeApps";

my $data = $tools->apps_get_pending_accounts();

my $text = "Hello! Please visit the following address to process these accounts: http://apps.magicjudges.org/accounts/review/\n";
my $goodlvl;
my $badlvl;
my $missing;

foreach my $user (@$data) {
    my $dci = $user->{'dci'};
    my $valid = $tools->checkvalid($dci);
    my $res = $tools->get_other_versions($dci);
    my $temp = '-'x60 . "\n";
    $temp .= sprintf('%10d %1d %s'."\n", $dci, $valid, $user->{'name'});
    my $gotany = 0;
    my $correctlevel = 0;
    foreach my $k (sort {$a <=> $b} keys %$res) {
        my $v = $res->{$k};
        #my $level = $tools->check_dcix_level($v) || 0;
        my $judge = $tools->dcix_force_import($v);
        my $level = $judge ? $judge->{'level'} : 0;
        my $name = $judge ? $judge->{'first'} .' '. $judge->{'last'} : '';
        next if $name eq ' ';
        my $location = $judge ? $judge->{'city'} .', '. $judge->{'region'} .', '. $judge->{'country'} : '';
        $temp .= sprintf('%10d => %10d: L%1d=>%1d, %s, %s'."\n", $dci, $v, $user->{'level'}, $level, $name, $location);
        $gotany = 1;
        if ($level >= $user->{'level'}) {
            $correctlevel = 1;
        }
    }
    if ($correctlevel) {
        $goodlvl .= $temp;
    } elsif ($gotany) {
        $badlvl .= $temp;
    } else {
        $missing .= $temp;
    }
}

if ($goodlvl) {
    $text .= '='x60 . "\n";
    $text .= '  ACCEPT IF NAME IS CORRECT' . "\n";
    $text .= $goodlvl;
}

if ($badlvl) {
    $text .= '='x60 . "\n";
    $text .= '  ACCEPT AS L0 IF NAME IS CORRECT' . "\n";
    $text .= $badlvl;
}

if ($missing) {
    $text .= '='x60 . "\n";
    $text .= '  DECLINE, NO RESULTS' . "\n";
    $text .= $missing;
}

print $text;

my $gmail = new Net::SMTP(
    'smtp.gmail.com',
    User     => '',
    Password => '',
    Port     => 465,
    SSL      => 1,
    Debug    => 1
);
$gmail->auth('', '')
    || die $gmail->message();
$gmail->mail('');
$gmail->to('') || die $gmail->message();
$gmail->data();
$gmail->datasend('To: "" <>'."\n");
$gmail->datasend("Subject: JudgeApps Pending Accounts\n");
$gmail->datasend("\n");
$gmail->datasend("$text\n");
$gmail->datasend("\n");
$gmail->dataend();
