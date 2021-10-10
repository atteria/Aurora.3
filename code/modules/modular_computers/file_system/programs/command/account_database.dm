#define FUND_CAP 1000000

/datum/computer_file/program/account_db
	filename = "accdb"
	filedesc = "Account Database"
	program_icon_state = "command"
	extended_desc = "Access transaction logs, account data and all kinds of other financial records."
	requires_ntnet = TRUE
	available_on_ntnet = FALSE
	size = 4 // primarily cloud computing
	usage_flags = PROGRAM_CONSOLE
	color = LIGHT_COLOR_BLUE

	var/machine_id = ""
	var/centcomm_db = FALSE

/datum/computer_file/program/account_db/New(obj/item/modular_computer/comp, var/is_centcomm_db = FALSE)
	..()
	if(current_map)
		machine_id = "[station_name()] Acc. DB #[SSeconomy.num_financial_terminals++]"
	else
		machine_id = "NT-Net Relay Back-up Software DB" // created during map generation inside the ntnet relay, not used by players

	centcomm_db = is_centcomm_db

/datum/computer_file/program/account_db/proc/get_held_card()
	var/obj/item/card/id/held_card
	if(computer.card_slot?.stored_card)
		held_card = computer.card_slot.stored_card
	return held_card

/datum/computer_file/program/account_db/proc/get_access_level()
	var/obj/item/card/id/held_card = get_held_card()
	if (!held_card)
		return 0
	if(access_cent_ccia in held_card.access)
		return 2
	else if((access_hop in held_card.access) || (access_captain in held_card.access))
		return 1

/datum/computer_file/program/account_db/proc/create_transation(target, reason, amount)
	var/datum/transaction/T = new()
	T.target_name = target
	T.purpose = reason
	T.amount = amount
	T.date = worlddate2text()
	T.time = worldtime2text()
	T.source_terminal = machine_id
	return T

/datum/computer_file/program/account_db/proc/accounting_letterhead(report_name)
	var/obj/item/card/id/held_card = get_held_card()
	return {"
		<center><h1><b>[report_name]</b></h1></center>
		<center><small><i>[station_name()] Accounting Report</i></small></center>
		<hr>
		<u>Generated By:</u> [held_card.registered_name], [held_card.assignment]<br>
	"}

/datum/computer_file/program/account_db/ui_interact(mob/user)
	var/datum/vueui/ui = SSvueui.get_open_ui(user, src)
	if(!ui)
		ui = new /datum/vueui/modularcomputer(user, src, "mcomputer-command-accountdb", 400, 640, filedesc)
	ui.open()

/datum/computer_file/program/account_db/vueui_transfer(oldobj)
	SSvueui.transfer_uis(oldobj, src, "mcomputer-command-accountdb", 400, 640, filedesc)
	return TRUE

/datum/computer_file/program/account_db/vueui_data_change(var/list/data, var/mob/user, var/datum/vueui/ui)
	. = ..()
	data = . || data || list()

	// Gather data for computer header
	var/headerdata = get_header_data(data["_PC"])
	if(headerdata)
		data["_PC"] = headerdata
		. = data

	var/obj/item/card/id/held_card = get_held_card()

	data["has_printer"] = !!computer.nano_printer
	data["id_card"] = held_card ? text("[held_card.registered_name], [held_card.assignment]") : FALSE
	data["access_level"] = get_access_level()
	data["machine_id"] = machine_id
	data["station_account_number"] = SSeconomy.station_account.account_number

	data["accounts"] = list()
	if(get_access_level())
		var/list/SSeconomy_accounts = centcomm_db ? SSeconomy.all_money_accounts : SSeconomy.get_public_accounts()
		for(var/M in SSeconomy_accounts)
			var/datum/money_account/D = SSeconomy.get_account(M)
			var/account_number = "[M]"
			data["accounts"][account_number] = list()
			data["accounts"][account_number]["no"] = D.account_number
			data["accounts"][account_number]["owner"] = D.owner_name
			data["accounts"][account_number]["sus"] = D.suspended
			data["accounts"][account_number]["money"] = D.money
			var/list/transactions = list()
			data["accounts"][account_number]["transactions"] = transactions
			for(var/datum/transaction/T in D.transactions)
				var/Tref = ref(T)
				transactions[Tref] = list()
				transactions[Tref]["d"] = T.date
				transactions[Tref]["t"] = T.time
				transactions[Tref]["tar"] = T.target_name
				transactions[Tref]["purp"] = T.purpose
				transactions[Tref]["am"] = T.amount
				transactions[Tref]["src"] = T.source_terminal

	return data

/datum/computer_file/program/account_db/Topic(href, href_list)
	if(..())
		return TRUE

	var/access_level = get_access_level()

	if(!access_level)
		return

	if(href_list["create_account"])
		var/account_name = href_list["create_account"]["name"]
		var/starting_funds = max(href_list["create_account"]["funds"], 0)

		starting_funds = Clamp(starting_funds, 0, SSeconomy.station_account.money)	// Not authorized to put the station in debt.
		starting_funds = min(starting_funds, FUND_CAP)								// Not authorized to give more than the fund cap.

		SSeconomy.create_account(account_name, starting_funds, src)

		if(starting_funds > 0)
			//subtract the money
			SSeconomy.station_account.money -= starting_funds

			//create a transaction log entry
			var/datum/transaction/trx = create_transation(account_name, "New account activation", "([starting_funds])")
			SSeconomy.add_transaction_log(SSeconomy.station_account,trx)

	if(href_list["suspend"])
		var/account = href_list["suspend"]["account"]

		var/datum/money_account/Acc = SSeconomy.get_account(account)
		if(Acc)
			Acc.suspended = !Acc.suspended
			callHook("change_account_status", list(Acc))


	if(href_list["add_funds"] && access_level == 2)
		var/account = href_list["add_funds"]["account"]
		var/amount = href_list["add_funds"]["amount"]

		var/datum/money_account/Acc = SSeconomy.get_account(account)
		if(Acc)
			log_and_message_admins("Added [amount] credits to the [Acc.owner_name] account.")
			Acc.money = min(Acc.money + amount, FUND_CAP)

	if(href_list["remove_funds"] && access_level == 2)
		var/account = href_list["remove_funds"]["account"]
		var/amount = href_list["remove_funds"]["amount"]

		var/datum/money_account/Acc = SSeconomy.get_account(account)
		if(Acc)
			log_and_message_admins("Removed [amount] credits to the [Acc.owner_name] account.")
			Acc.money = max(Acc.money - amount, -FUND_CAP)

	if(href_list["revoke_payroll"])
		var/account = href_list["revoke_payroll"]["account"]

		var/datum/money_account/Acc = SSeconomy.get_account(account)
		if(Acc)
			var/funds = Acc.money
			var/account_trx = create_transation(SSeconomy.station_account.owner_name, "Revoke payroll", "[funds]")
			var/station_trx = create_transation(Acc.owner_name, "Revoke payroll", funds)

			SSeconomy.station_account.money += funds
			Acc.money = 0

			SSeconomy.add_transaction_log(Acc,account_trx)
			SSeconomy.add_transaction_log(SSeconomy.station_account,station_trx)

			callHook("revoke_payroll", list(Acc))


	if(href_list["print"])

		var/text
		var/pname
		var/datum/money_account/Acc = SSeconomy.get_account(href_list["print"])
		if(Acc)
			pname = "account #[Acc.account_number] details"
			var/title = "Account #[Acc.account_number] Details"
			text = {"
				[accounting_letterhead(title)]
				<u>Holder:</u> [Acc.owner_name]<br>
				<u>Balance:</u> [Acc.money]电<br>
				<u>Status:</u> [Acc.suspended ? "Suspended" : "Active"]<br>
				<u>Transactions:</u> ([Acc.transactions.len])<br>
				<table>
					<thead>
						<tr>
							<td>Timestamp</td>
							<td>Target</td>
							<td>Reason</td>
							<td>Value</td>
							<td>Terminal</td>
						</tr>
					</thead>
					<tbody>
				"}

			for (var/datum/transaction/T in Acc.transactions)
				text += {"
							<tr>
								<td>[T.date] [T.time]</td>
								<td>[T.target_name]</td>
								<td>[T.purpose]</td>
								<td>[T.amount]</td>
								<td>[T.source_terminal]</td>
							</tr>
					"}

			text += {"
					</tbody>
				</table>
				"}

		else
			pname = "financial account list"
			text = {"
				[accounting_letterhead("Financial Account List")]
				<table>
					<thead>
						<tr>
							<td>Account Number</td>
							<td>Holder</td>
							<td>Balance</td>
							<td>Status</td>
						</tr>
					</thead>
					<tbody>
			"}

			var/list/SSeconomy_accounts = centcomm_db ? SSeconomy.all_money_accounts : SSeconomy.get_public_accounts()
			for(var/M in SSeconomy_accounts)
				var/datum/money_account/D = SSeconomy.get_account(M)
				text += {"
						<tr>
							<td>#[D.account_number]</td>
							<td>[D.owner_name]</td>
							<td>[D.money]电</td>
							<td>[D.suspended ? "Suspended" : "Active"]</td>
						</tr>
				"}

			text += {"
					</tbody>
				</table>
			"}

		var/obj/item/paper/P = computer.nano_printer.print_text("", pname, "#deebff")
		P.set_content_unsafe(pname, text)

	SSvueui.check_uis_for_change(src)

#undef FUND_CAP
