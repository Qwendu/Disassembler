#scope_export
#module_parameters(ENABLE :bool = true);

Plugin :: struct
{
	using #as base : Jai.Metaprogram_Plugin;

	procedures_to_disassemble : [..] Disassembled_Procedure;
	assembly_files : [..] string;
	base_folder : string;
}

Disassembled_Procedure :: struct
{
	name : string;
	symbol_name : string;
	file_of_definition : string;
	runtime_address : u64;
	binary : [] u8;
	disassembled : [] Zydis.DisassembledInstruction;
	file_index : int = -1;
	labels : [] Label;
}

Label :: struct
{
	address : u64;
	name : string;
};



get_plugin :: () -> *Jai.Metaprogram_Plugin
{
	plug := New(Plugin);
	plug.message = xx message;
	plug.finish = xx finish;
	
	array_add(*plug.assembly_files, "all.asm");

	return plug;
}




#scope_file


finish :: (using plugin : *Plugin)
{
	builders := NewArray(assembly_files.count, String_Builder);

	for * proc : procedures_to_disassemble
	{
		if proc.binary.data
		{
			continue_disassembly := true;
			{
				labels : [..] Label;
				defer proc.labels = labels;
				array_add(*labels, .{
					address = proc.runtime_address,
					name    = proc.symbol_name, 
				});


				str : [] u8;
				str.data  = proc.binary.data;
				str.count = proc.binary.count;
				disassembled_up_to := proc.runtime_address;
				highest_jump_to    := proc.runtime_address;
				instr_idx := 0;
				while true
				{
					defer if disassembled_up_to >= cast(u64)proc.binary.count  + proc.runtime_address  break;
					succ, instr := Zydis.DisassembleIntel(.LONG_64, xx disassembled_up_to, str);
					if succ != 0 && succ != 0x100000
					{
						log("Failed to disassemble instruction at offset +% [%]. Stopping disassembly of function %.", disassembled_up_to, formatInt(succ, base=16), proc.name);
						proc.binary.count = 0;
						continue_disassembly = false;
						break;
					}

					meta := instr.info.meta;

					is_jump, jump_address := is_Jump(instr);
					if is_jump
					{
						highest_jump_to = max(jump_address, highest_jump_to);
						array_add(*labels, .{address = jump_address, name = tprint("%p%", proc.symbol_name, jump_address - proc.runtime_address)});
					}

					instr_idx += 1;
					disassembled_up_to += instr.info.length;
					str.data           += instr.info.length;
					str.count          -= instr.info.length;


					if meta.category == .RET
					{
						if highest_jump_to < disassembled_up_to
						{
							//log("Found return of function % at +% [% instructions]", proc.symbol_name, disassembled_up_to - proc.runtime_address, instr_idx);
							proc.binary.count = xx disassembled_up_to;
							proc.disassembled = NewArray(instr_idx, Zydis.DisassembledInstruction);
							break;
						}
					}
				}
			}


			if !continue_disassembly 
			{
				log_error("Zydis failed to disasseble procedure %", proc.name);
				continue;
			}

			quick_sort(proc.labels,  a => a.address);
			// Deduplicate entries
			{
				for proc.labels  log("%", it.name);
				last_idx  := 0;
				for 1..proc.labels.count-1
				{
					if proc.labels[last_idx].address != proc.labels[it].address
					{
						last_idx += 1;
						proc.labels[last_idx] = proc.labels[it];
					}
				}
				for proc.labels  log("%", it.name);
			}

			{
				addr := proc.runtime_address;
				data := proc.binary;
				for * instr : proc.disassembled
				{
					_, instr.* = Zydis.DisassembleIntel(.LONG_64, xx addr, data);
					addr       += instr.info.length;
					data.data  += instr.info.length;
					data.count -= instr.info.length;
				}
			}
	
			{
				log("Disassembling % into %", proc.name, assembly_files[proc.file_index]);
				label_index := 0;
				builder := *builders[proc.file_index];
				append(builder, "# Function ");
				append(builder, proc.name);
				append(builder, "\n");
				for instr : proc.disassembled
				{
					for proc.labels
					{
						if it.address == instr.runtime_address
						{
							if it.name  append(builder, it.name);
							else print_to_builder(builder, "%p%", proc.symbol_name ,formatInt(it.address - proc.runtime_address,base=16));
							append(builder, ":\n");
						}
					}
					//log("%: %", formatInt(instr.runtime_address,base=16), to_string(instr.text));
					append(builder, "\t");
					is_Jump, jump_addr := is_Jump(instr);
					if !is_Jump  append(builder, Zydis.GetInstructionString(instr));
					else{
						instr_string := Zydis.GetInstructionString(instr);
						found, instr, rest := split_from_left(instr_string, #char " ");
						assert(found);
						append(builder, instr);
						append(builder, " ");
						for proc.labels
						{
							if it.address == jump_addr  {append(builder, it.name); break;}
						}
					}
					append(builder, "\n");
				}
				append(builder, "\n\n");
			}
		}else{
			log_error("Could not find a binary for procedure %. Skipping", proc.name);
		}
	}

	
	if procedures_to_disassemble.count != 0
	{
		for *builders
		{
			file_path := tprint("%/%", base_folder, assembly_files[it_index]);
			if !it.initialized
			{
				if file_exists(file_path)
				{
					// Avoid confusing the user, when they recompile and removed
					//  an annotation, but they still see the disassembly of a 
					//  previous compilation
					file_delete(file_path);
					log("Deleting file % because we are not writing to it in this build", file_path);
				}
				continue;
			}
			


			write_entire_file(file_path,it, do_reset = true);
		}
	}
}

message :: (using plugin : *Plugin, msg : *Jai.Message)
{
	#if ENABLE
	{
		if msg.kind == .TYPECHECKED
		{
			typechecked := cast(*Jai.Message_Typechecked)msg;

			for typechecked.procedure_headers
			{
				for note : it.expression.notes
				{
					found, dis_note, file_name := split_from_left(note.text, #char "(");
					file_name.count -= 1;
					file_index := ifx found then get_Asm_File(plugin, file_name) else 0;
					if dis_note == "Disassemble"
					{
						array_add(*procedures_to_disassemble, .{
							name = it.expression.name,
							file_index = file_index
						});
						log("Disassembling procedure %, putting it in file %", it.expression.name, assembly_files[file_index]);
						break note;
					}

				}

			}
		}
		if msg.kind == .PHASE
		{
			for complete: 0..0
			{
				postcomp := cast(*Jai.Message_Phase)msg;
				if postcomp.phase != .POST_WRITE_EXECUTABLE  break;
				
				build_options := Jai.get_build_options(plugin.workspace);
				base_folder    = build_options.intermediate_path;
				
				for coff_file_name : postcomp.compiler_generated_object_files
				{
					success, coff := parse_coff_file(coff_file_name);
					if !success  {
						log("Failed to load %", coff_file_name);
						continue;
					}
					
					for sym, sym_idx : coff.symbols
					{
						if sym.storage_class != .EXTERNAL  continue;

						symbol_name, found_symbol := get_symbol_name(coff, sym_idx);
						if !found_symbol  continue;
						_, function_name, hash := split_from_right(symbol_name, #char "_");
						disasm, index := should_disassemble(plugin, function_name);
						if disasm 
						{
							proc := *plugin.procedures_to_disassemble[index];
							if proc.symbol_name && proc.symbol_name != symbol_name
							{
								log_error("Procedure % has multiple definitions, at least \n[1]: %\n[2]: %\nChoosing [2]", proc.name, proc.symbol_name, symbol_name);
							}
							proc.symbol_name        = symbol_name;
							proc.file_of_definition = coff_file_name;
							if sym.section_number == 0
							{
							}else{
								section           := sym.section_number - 1;
								section_ptr       := *coff.section_headers[section];
								offset_in_section := sym.value;
								section_data := get_section_data(coff, section);
								proc.binary.data  = cast(*u8)(section_data.data + offset_in_section);
								proc.binary.count = section_data.count - offset_in_section;
								proc.runtime_address = section_ptr.virtual_address + offset_in_section;
							}
						}
					}
				}

				
			}
		}


		
	}
}

get_Asm_File :: (using plugin : *Plugin, file_name : string) -> int
{
	for assembly_files
	{
		if it == file_name  return it_index;
	}
	array_add(*assembly_files, file_name);
	return assembly_files.count - 1;
}

should_disassemble :: (plugin : *Plugin, name : string) -> bool, int
{
	for plugin.procedures_to_disassemble
	{
		if name == it.name
		{
			return true, it_index;
		}
	}
	return false, -1;
}

is_Jump :: (instr : Zydis.DisassembledInstruction) -> bool, u64
{
	if instr.info.mnemonic ==
	{
	case .JB   ; #through;
	case .JBE  ; #through;
	case .JCXZ ; #through;
	case .JECXZ; #through;
	case .JKNZD; #through;
	case .JKZD ; #through;
	case .JL   ; #through;
	case .JLE  ; #through;
	case .JMP  ; #through;
	case .JNB  ; #through;
	case .JNBE ; #through;
	case .JNL  ; #through;
	case .JNLE ; #through;
	case .JNO  ; #through;
	case .JNP  ; #through;
	case .JNS  ; #through;
	case .JNZ  ; #through;
	case .JO   ; #through;
	case .JP   ; #through;
	case .JRCXZ; #through;
	case .JS   ; #through;
	case .JZ   ; 

	case;
		return false, 0;
	}
	assert(instr.info.operand_count_visible == 1, "Jumps have one address operand");
	op := instr.operands[0];

	if op.type == .REGISTER
	{
		log_error("Jumpig using a register as a base at +%, we dont know how far we jump", instr.runtime_address);
	}

	if op.type == .IMMEDIATE
	{
		if op.imm.is_relative
		{
			return true, cast(u64)(cast(s64)instr.runtime_address + instr.info.length + op.imm.value.s);
		}else{
			assert(false, "Hardcoding immediate jumps?");
			return true, op.imm.value.u;
		}
	}
	
	
	

	return true, 0;
}


Jai :: #import "Compiler";
#import "Basic";
#import "Process";
#import "executable_formats";
#import "String";
Zydis :: #import,dir "jai-zydis";
#import "File";
#import "Sort";
#import "File_Utilities";
