#!/bin/bash

# sync data to lfs603 customer folder 
# generates email and sends to customer
usage() {
    echo "Usage: ctg-deliver -u CTG-USER-LFS -d DATA-TO-DELIVER ( -c CUSTOMER-USER-LFS )"  1>&2 
    echo ""
    echo ""
    echo "needs ctg-delivery.info.csv in delivery folder (-d DATA-TO-DELIVER) of the format:"
    echo "projid,<PROJID>"
    echo "email,<customer email adress>"
    echo "pipeline,<ctg-pipeline>"
}

exit_abnormal() {
    usage
    exit 1
}


while getopts u:d:cm:i:p: opt; do
    case $opt in
	u) ctguser="$OPTARG"
	   ;;
	d) data="$OPTARG"
	    ;;
	c) customer="$OPTARG"
	    ;;
	\?) echo "> Error: Invalid option -$OPTARG" >&2
	    exit_abnormal ;;
	:) echo "> Error: -${OPTARG} requires an argument!" 
	    exit_abnormal ;;
    esac
done

shift "$(( OPTIND -1 ))"

if [ -z $ctguser ]; then
    echo "> Error: missing -u CTG-USER-LFS!"
    exit_abnormal
fi
if [ -z $data ]; then
    echo "> Error: missing -d DATA-TO-DELIVER!"
    exit_abnormal
fi 
if [ -z $customer ]; then
    echo "> missing -c CUSTOMER-USER-LFS!"
    echo " .. will use ctg-delivery.info.csv project id."
fi

# READ ctg-delivery.info.csv within delivery folder 
delinfo="$data/ctg-delivery.info.csv"

# Generate pswd
pswd=$(sh /projects/fs1/shared/ctg-tools/bin/ctg-password-generator.sh)

if [ -f $delinfo ]; then
    
    email=$(grep "email," $delinfo | cut -f2 -d"," | tr -d '\n\r' | sed "s/;/ /g")
    pid=$(grep "projid," $delinfo | cut -f2 -d"," | tr -d '\n\r')
    pipe=$(grep "pipeline," $delinfo | cut -f2 -d"," | tr -d '\n\r')

    if [ -z "$email" ]; then
	echo "> Error: no customer email found in $delinfo.. this file needs a row with 'email,<customer mail adress>'"
	exit_abnormal
    fi 
    if [ -z $pid ]; then
	echo "> Error: no projid  found in $delinfo.. this file needs a row with 'projid,<ctg-project id>'"
	exit_abnormal
    fi 
    if [ -z $pipe ]; then
	echo "> Error: no pipeline found in $delinfo.. this file needs a row with 'pipeline,<ctg-pipeline>'"
	exit_abnormal
    fi 
else
    echo ">Error: No ctg-delivery.info.csv found in $data folder! "
    exit_abnormal
fi

if [ -z $customer ]; then
    customer="ctg_${pid}"
fi

# Set target folder 
lfstarget="/srv/data/$customer/$data"

# Delivery template for current pipeline
emailtemplate="/projects/fs1/shared/ctg-pipelines/ctg-${pipe}/ctg-delivery-mail/ctg-delivery-mail_${pipe}.csv"

# Check if template for this pipeline exists
if [ ! -f $emailtemplate ]; then
    echo "> Error: template email for pipeline $pipe ($emailtemplate) does NOT exist. Please add (or check if pipeline name is correct and corresponding to a template in $emailtemplate) "
    exit_abnormal
fi

# Set new mail txt file (this is the one that will be modified and sent to the customer)
newmail="${data}/ctg-delivery-mail.$pid.txt"
# Set scp command for customer (this command will be  put in the emal)
scpcmd="scp -P 22022 -r $customer@lfs603.srv.lu.se:$lfstarget ."

# bash script for sending mail - to sync to lfs and execute via ssh

# Add CTG BNF user email as "cc" and "from" : so both customer and ctg bnf'er will get the email
# Set to Pers adress by default (ADD IF STATEMENTS FOR OTHER CTG USERS)
ctgmail="per.brattas@med.lu.se" 

ctgName="CTG data delivery"  # This goes as "Sender name" of the email (with the "ctgmail" as from adress)

if [ $ctguser == "per" ]; then
    ctgmail="per.brattas@med.lu.se"

elif [ $ctguser == "percebe" ]; then
    ctgmail="david.lindgren@med.lu.se"
fi


## ATTACHMENTS
# If sc-rna-10x : attach websummaries
att=""
if [[ "$pipe" == "sc-rna-10x" ]]; then
    # attach web summaries (.tar.gz)
    echo "> sc-rna-10x delivery: tar zip web-summaries for attaching to mail.."
    tar -zcvf $data/summaries/web-summaries.tar.gz $data/summaries/web-summaries
    file="$data/summaries/web-summaries.tar.gz"
    file2="/srv/data/$customer/$file" 
    att="$att -a $file2"
fi

# attach multiqc report
# if rawdata, take ctg-interop from runfolder
if [[ "$pipe" == "rawdata" ]]; then
    mult=$(ls $data/ctg-interop/*.html)
    file2="/srv/data/$customer/${mult}"
    att="$att -a $file2"
# else, take qc/multiqc/*html
else
    mult=$(ls $data/qc/multiqc/*report.html)
    file2="/srv/data/$customer/$mult"
    att="$att -a $file2"
fi

# attach ctg-delivery guide
att="$att -a /srv/data/$ctguser/ctg-delivery-guide-v1.0.pdf"

# Command to execute for sending the email 
mailcmd="echo '' | mutt -s 'CTG $pipe delivery of $pid' $email -i /srv/data/$customer/$newmail -e 'unmy_hdr from; my_hdr From: ${ctgName} <${ctgmail}>' -e 'set content_type=text/html' -c ${ctgmail} $att"
#mailcmd_mailx="mailx -s 'CTG $pipe delivery of $pid' -a 'Content-Type: text/html' -a 'From: $ctgName <${ctgmail}>' $email $ctgmail < /srv/data/$customer/$newmail"

echo ""
echo "> Mutt command:"
echo $mailcmd

# Create the script that will execute the email delivery (the script will be sent to lfs delivery folder, and executed via ssh below in this current script..)
mailscr="${data}/ctg-delivery.$pid.$pipe.sh"
echo $mailcmd > $mailscr

# Adress of this email-sending script on lfs
lfsmailscr="/srv/data/$customer/$mailscr"
lfsmail="/srv/data/$customer/$newmail"

# Remove '/' suffix from data folder
newdata=$(echo $data | sed 's/\/$//')
data=$newdata

cmd="/usr/bin/rsync -av --progress $data $ctguser@lfs603.srv.lu.se:/srv/data/$customer/"

echo ""
echo "> The following arguments are entered:"
echo " - CTG user          : $ctguser"
echo " - CTG Email         : $ctgmail" 
echo " - Customer lfs-user : $customer"
echo " - Customer email    : $email"
echo " - Delivery data     : $data"
echo " - Project ID        : $pid"
echo " - CTG-Pipeline      : $pipe" 
echo "-- LFS info -- "
echo " - lfs dir  : $lfstarget"
echo " - mail scr : $lfsmailscr"
echo " - mail txt : $lfsmail"
echo ""
echo "> Current command will be executed: "
echo "> $cmd"
echo ""
echo ""

echo ".. Creating delivery email"
echo "> Using delivery email template: $emailtemplate"
# Modify the email to contain project ID and download command for customer
cp $emailtemplate $newmail
sed "s/xxprojidxx/${pid}/g" $newmail > tmp.txt; mv tmp.txt $newmail
sed "s|xxdownloadcommandxx|${scpcmd}|g" $newmail > tmp.txt; mv tmp.txt $newmail
sed "s|xxpasswordxx|${pswd}|g" $newmail > tmp.txt;  mv tmp.txt $newmail
rm -f tmp.txt
echo "> Modified delivery email"; echo ""
echo ""; echo "";
    
## Check if customer exist
sshcmd="$(cat <<EOF
if [ -d /srv/data/${customer} ]; then
echo '1'
else
echo '2'
fi
EOF
)"

# If user does not exists (ssh command returns 2), create user 
userExist=$(ssh -t -t $ctguser@lfs603.srv.lu.se "$sshcmd")
if [[ "$userExist" != "1" ]]; then
    echo "-- > user '${customer}' does not exist.. creating user with password"
    
    createcmd="ssh $ctguser@lfs603.srv.lu.se sh /srv/data/create_customer_account.sh $customer <<EOF
$pswd
$pswd
EOF"
    
    #	    echo "$createcmd "
    echo "$createcmd" | bash -
    
    echo ".. changing permissions on customer folder"
    mod="ssh $ctguser@lfs603.srv.lu.se sudo chmod g+s /srv/data/$customer "
    echo "- $mod"
    $mod
    umod="ssh $ctguser@lfs603.srv.lu.se sudo usermod -a -G ${customer} $ctguser"
    echo "- $umod"
    $umod
    cmod="ssh $ctguser@lfs603.srv.lu.se sudo chmod 770 /srv/data/${customer}"
    echo "- $cmod"
    $cmod
fi

echo ".. Starting rsync .."; echo ""
echo "$cmd"
$cmd | tee snc.$data.log 
echo ""
echo "> Changing permissions and ownership of delivery folder.."

mod="ssh $ctguser@lfs603.srv.lu.se sudo chmod 770 -R /srv/data/$customer"
own="ssh $ctguser@lfs603.srv.lu.se sudo chown -R ${customer}:$ctguser /srv/data/$customer"
echo "- $mod"
echo "- $own" 
echo ""
$mod
$own

echo "> Setting 'postconf -e message_size_limit=202400000' on lfs603"
postconfcmd="ssh $ctguser@lfs603.srv.lu.se sudo postconf -e message_size_limit=202400000"
echo "- $postconfcmd"
$postconfcmd

echo ""
echo "> Sending email to customers: $email"
emailcmd="ssh $ctguser@lfs603.srv.lu.se bash $lfsmailscr"
echo "- $emailcmd"
$emailcmd

# Delete ctg-delivery files from deliver folder
# Delete mail script
echo ""
echo "> Deleting mail info, script and html"
delcmd="ssh $ctguser@lfs603.srv.lu.se rm -r -f $lfsmailscr"
echo "- $delcmd"
$delcmd

# Delete delivery email
delcmd="ssh $ctguser@lfs603.srv.lu.se rm -r -f $lfstarget/ctg-delivery-mail.$pid.txt"
echo "- $delcmd"
$delcmd

# Delete ctg-delivery info
delcmd="ssh $ctguser@lfs603.srv.lu.se rm -r -f $lfstarget/ctg-delivery.info.csv"
echo "- $delcmd"
$delcmd

echo ""
echo "> Customer download command:"
echo $scpcmd

echo ""
echo "> rsync log file:" 
echo " - current dir: snc.$data.log "
echo 
echo "Done"


