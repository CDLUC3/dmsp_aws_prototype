function DisplayDateDate(str, showTime) {
  let dt = new Date(Date.parse(str))?.toDateString()?.split(' ');
  let tm = new Date(Date.parse(str))?.toLocaleTimeString()?.split(':');
  let localTime = `${('0' + tm[0]).slice(-2)}${tm.slice(-1)?.toString()?.split(' ')?.slice(-1)}`;
  return showTime ? [dt[2], dt[1], dt[3], localTime].join(' ') : [dt[2], dt[1], dt[3]].join(' ');
}

export default DisplayDateDate;
